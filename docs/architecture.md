# Architecture

Vikunja running on Amazon EKS, provisioned with Terraform, deployed with ArgoCD,
secured with cert-manager and reachable at `https://eks.labs.younesblog.org`.

The architecture is split into four diagrams. Read them in order.

1. [AWS infrastructure](#1-aws-infrastructure): what exists in AWS
2. [Request flow, DNS and TLS](#2-request-flow-dns-and-tls): how a user reaches the app
3. [CI/CD and GitOps](#3-cicd-and-gitops): how code becomes a running app
4. [Monitoring](#4-monitoring): how the cluster is observed

---

## 1. AWS infrastructure

Everything lives in one VPC in `eu-west-2`, spread over two availability zones.
Worker nodes sit in **private** subnets and have no public IPs. The load balancer
sits in the **public** subnets. The nodes reach the internet (ECR, Let's Encrypt)
outbound only, through the NAT gateway.

```mermaid
flowchart TB
    internet(["Internet"])

    subgraph aws["AWS account, region eu-west-2"]
        r53["Route 53 hosted zone<br/>labs.younesblog.org"]
        ecr["ECR repository: vikunja"]
        s3["S3 bucket<br/>Terraform state"]

        subgraph iam["IAM roles"]
            clusterrole["EKS cluster role"]
            noderole["Node role<br/>worker policy, CNI, ECR read"]
            extdnsrole["ExternalDNS role<br/>Route 53 access, one zone only"]
            lbcrole["Load Balancer Controller role"]
        end

        eks["EKS control plane<br/>managed by AWS, Kubernetes 1.35"]

        subgraph vpc["VPC 10.0.0.0/16"]
            igw["Internet gateway"]

            subgraph az1["Availability zone eu-west-2a"]
                pub1["Public subnet 10.0.1.0/24<br/>NAT gateway and NLB"]
                priv1["Private subnet 10.0.3.0/24<br/>worker node"]
            end

            subgraph az2["Availability zone eu-west-2b"]
                pub2["Public subnet 10.0.2.0/24<br/>NLB"]
                priv2["Private subnet 10.0.4.0/24<br/>worker node"]
            end

            sg["Cluster security group<br/>node to node and control plane: all traffic<br/>NLB to Traefik: TCP 8000 and 8443<br/>outbound: all"]
        end
    end

    internet <--> igw
    igw <--> pub1
    igw <--> pub2
    pub1 -->|"NAT: outbound only"| priv1
    pub1 -->|"NAT: outbound only"| priv2
    pub1 -->|"NLB forwards to pods"| priv1
    pub2 -->|"NLB forwards to pods"| priv2
    eks -.->|"manages"| priv1
    eks -.->|"manages"| priv2
    sg -.->|"attached to nodes"| priv1
    sg -.->|"attached to nodes"| priv2
    clusterrole -.-> eks
    noderole -.-> priv1
    noderole -.-> priv2
    priv1 -->|"pull images"| ecr
    priv2 -->|"pull images"| ecr
```

| Part | What it does |
|---|---|
| Public subnets | Have a route to the internet gateway. Hold the NAT gateway and the load balancer. |
| Private subnets | Route outbound traffic to the NAT gateway. Hold the worker nodes, so nothing on the internet can connect to them directly. |
| Cluster security group | Created by EKS. Terraform adds one rule so the load balancer can reach Traefik. |
| IAM roles | The cluster and node roles are used by EKS and EC2. ExternalDNS and the load balancer controller each get their own role through EKS Pod Identity, so only those pods get those permissions. |
| S3 bucket | Remote Terraform state with versioning, encryption and lockfile locking. |

---

## 2. Request flow, DNS and TLS

This shows what happens when someone opens `https://eks.labs.younesblog.org`,
and how the DNS record and certificate got there in the first place.

```mermaid
flowchart LR
    user(["User browser"])

    subgraph aws["AWS"]
        r53["Route 53<br/>labs.younesblog.org"]
        nlb["Network Load Balancer<br/>internet-facing"]
    end

    subgraph cluster["EKS cluster"]
        subgraph traefikns["namespace: traefik"]
            traefik["Traefik<br/>ingress controller"]
        end

        subgraph appns["namespace: default"]
            ingress["Ingress: vikunja<br/>host eks.labs.younesblog.org"]
            svc["Service: vikunja<br/>port 80"]
            pod["Vikunja pod<br/>port 3456"]
            tlssecret[("Secret: vikunja-tls")]
        end

        subgraph platform["Platform controllers"]
            lbc["AWS Load Balancer Controller"]
            extdns["ExternalDNS"]
            certmgr["cert-manager<br/>ClusterIssuer: letsencrypt"]
        end
    end

    le["Let's Encrypt"]

    user -->|"1. DNS lookup"| r53
    r53 -->|"2. returns NLB address"| user
    user -->|"3. HTTPS request"| nlb
    nlb -->|"4. forwards to pod IP"| traefik
    traefik -->|"5. matches host and path"| ingress
    ingress --> svc
    svc --> pod
    traefik -.->|"reads certificate"| tlssecret

    lbc -.->|"creates and updates"| nlb
    extdns -.->|"watches Ingress, writes record"| r53
    ingress -.->|"annotation asks for a certificate"| certmgr
    certmgr -->|"HTTP-01 challenge"| le
    le -->|"checks challenge URL through"| nlb
    certmgr -.->|"stores certificate"| tlssecret
```

**Walking through it**

1. **Load balancer:** Traefik's Service asks for a load balancer. The AWS Load Balancer Controller creates the NLB and registers Traefik's pod IPs as targets.
2. **DNS:** ExternalDNS sees the Ingress host and writes a record into Route 53 pointing at the NLB.
3. **Certificate:** the Ingress carries a cert-manager annotation. cert-manager asks Let's Encrypt for a certificate and proves domain ownership with an HTTP-01 challenge, which Let's Encrypt checks through the same NLB and Traefik. The certificate is stored in the `vikunja-tls` Secret.
4. **A request:** the browser looks up the name in Route 53, connects to the NLB over HTTPS, and Traefik presents the certificate. Traefik then routes the request to the Vikunja Service and pod.

---

## 3. CI/CD and GitOps

Terraform builds the cloud infrastructure. ArgoCD keeps the cluster matching what
is in Git. GitHub Actions never touches the cluster directly. It only builds
images and commits changes to Git.

```mermaid
flowchart TB
    dev(["Developer push to main"])
    repo[("GitHub repository")]

    subgraph gha["GitHub Actions, authenticated to AWS with OIDC"]
        tf["terraform.yml<br/>fmt, validate, plan, apply"]
        sec["security.yml<br/>Checkov scan of Terraform"]
        dock["docker.yml<br/>build, Trivy scan, push to ECR,<br/>update image tag in manifest"]
    end

    subgraph aws["AWS"]
        s3["S3 state bucket"]
        infra["VPC, EKS, IAM, Route 53"]
        ecr["ECR"]
    end

    subgraph cluster["EKS cluster"]
        argo["ArgoCD<br/>namespace: argocd"]
        root["root-app"]
        apps["Child apps<br/>vikunja, traefik, cert-manager,<br/>external-dns, load balancer controller,<br/>metrics-server, monitoring,<br/>cluster-issuer"]
        workloads["Running workloads"]
    end

    dev --> repo
    repo -->|"changes in terraform/"| tf
    repo -->|"changes in terraform/"| sec
    repo -->|"changes in vikunja/"| dock

    tf <-->|"state and lock"| s3
    tf -->|"creates"| infra
    dock -->|"push image tagged with commit SHA"| ecr
    dock -->|"commit new tag to deployment.yaml"| repo

    argo -->|"polls Git"| repo
    root --> apps
    argo --> root
    apps -->|"sync"| workloads
    ecr -->|"nodes pull image"| workloads
```

**The loop that matters**

1. You push a change under `vikunja/`.
2. `docker.yml` builds the image, scans it with Trivy (the job fails on HIGH or CRITICAL findings), pushes it to ECR tagged with the commit SHA, then commits that SHA into `kubernetes/app/vikunja-deployment.yaml`.
3. ArgoCD sees the new commit and updates the Deployment, and Kubernetes pulls the new image from ECR.

The `root-app` is an app-of-apps. It points at `kubernetes/argo-cd/`, and every
file there is a child Application. With `selfHeal` and `prune` on, anything changed
by hand in the cluster is put back to what Git says.

**Not automated yet**

- ArgoCD itself is installed by hand and is not in this repo.
- The `grafana-admin` Secret is created by hand with `kubectl`.
- The VPC ID in `aws-load-balancer-controller.yml` is pasted in from `terraform output vpc_id` after each build.

---

## 4. Monitoring

kube-prometheus-stack runs in the `monitoring` namespace. Prometheus collects
metrics from the nodes, the pods and Traefik, and Grafana draws them.

```mermaid
flowchart LR
    subgraph sources["Metric sources"]
        ne["node-exporter<br/>node CPU, memory, disk"]
        ksm["kube-state-metrics<br/>pod, node and deployment state"]
        cadvisor["kubelet and cAdvisor<br/>container CPU and memory"]
        traefikm["Traefik metrics<br/>requests, status codes, latency"]
    end

    subgraph mon["namespace: monitoring"]
        prom["Prometheus<br/>3 day retention"]
        graf["Grafana"]
        am["Alertmanager"]
        operator["Prometheus Operator<br/>reads ServiceMonitors"]
    end

    ms["metrics-server<br/>kubectl top"]
    adminuser(["Admin"])
    traefik["Traefik ingress"]
    cert["cert-manager and ExternalDNS<br/>grafana.labs.younesblog.org"]

    ne --> prom
    ksm --> prom
    cadvisor --> prom
    traefikm -->|"ServiceMonitor"| operator
    operator -.->|"configures scrape targets"| prom
    prom -->|"data source"| graf
    prom -->|"alert rules"| am
    adminuser -->|"HTTPS"| traefik
    traefik --> graf
    cert -.->|"DNS record and certificate"| traefik
```

| Component | Role |
|---|---|
| Prometheus | Scrapes and stores metrics. Configured to pick up ServiceMonitors from every namespace. |
| Grafana | Shows dashboards. Ships with the standard Kubernetes cluster, node, namespace and pod dashboards, plus the official Traefik dashboard for ingress traffic. Reached through Traefik with a Let's Encrypt certificate. |
| Alertmanager | Receives alerts from Prometheus rules. No receivers are configured yet. |
| metrics-server | Provides `kubectl top` and resource metrics to the Kubernetes API. It is separate from Prometheus. |
