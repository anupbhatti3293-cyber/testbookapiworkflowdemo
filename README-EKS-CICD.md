# TestBook API --- GitHub Actions CI/CD to Amazon EKS

This guide creates a complete demonstration pipeline:

**Git push → GitHub Actions → Maven tests/build → Docker image → Amazon
ECR → Amazon EKS → Kubernetes rolling deployment → AWS Load Balancer**

It is written for the existing `testbookapiworkflowdemo` project.

## Values used in this lab

  Setting                 Value
  ----------------------- ------------------------
  AWS Region              `eu-north-1`
  AWS Account             `316255801172`
  ECR repository          `mybookapi`
  EKS cluster             `testbook-cluster`
  Kubernetes Deployment   `testbook-api`
  Kubernetes Service      `testbook-service`
  Application port        `8080`
  Git branch              `main`
  GitHub AWS role         `GitHubActionsECRRole`

If your real values differ, change them in the workflow before running
it.

------------------------------------------------------------------------

# 1. What this demonstration teaches

There are two parts.

**CI --- Continuous Integration**

1.  A developer pushes code to `main`, or manually starts the workflow.
2.  GitHub downloads the repository.
3.  Java 17 is prepared.
4.  Maven runs the tests and builds the application.
5.  GitHub authenticates to AWS using OIDC.
6.  Docker builds an image.
7.  The image is tagged with the Git commit SHA.
8.  The image is pushed to Amazon ECR.

**CD --- Continuous Deployment**

1.  GitHub authenticates to AWS again.
2.  GitHub connects `kubectl` to the EKS cluster.
3.  The Kubernetes Service is created/updated.
4.  On the first run, the Deployment is created.
5.  The Deployment is changed to use the new ECR image.
6.  Kubernetes performs a rolling deployment.
7.  GitHub waits for the rollout to finish.
8.  The workflow displays Pods, Deployment and Service information.

There is **no SSH or PEM file** in this EKS deployment. GitHub talks to
the EKS/Kubernetes API instead of logging into an EC2 server.

------------------------------------------------------------------------

# 2. Final repository structure

Create this structure:

``` text
testbookapiworkflowdemo/
├── src/
├── pom.xml
├── Dockerfile
├── kubernetes/
│   ├── deployment.yaml
│   └── service.yaml
└── .github/
    └── workflows/
        └── 03-eks-cicd.yml
```

The downloadable files supplied with this guide are:

-   `03-eks-cicd.yml`
-   `deployment.yaml`
-   `service.yaml`

Put them in the locations shown above.

------------------------------------------------------------------------

# 3. Prerequisites

You need:

1.  An AWS account.
2.  Your GitHub repository.
3.  Dockerfile in the repository.
4.  AWS CLI on your Mac.
5.  `kubectl`.
6.  `eksctl`.
7.  An ECR repository.
8.  An EKS cluster with worker nodes.
9.  GitHub OIDC configured in AWS.
10. An IAM role that GitHub Actions can assume.
11. That IAM role must also be authorised to use the EKS cluster.

AWS recommends EKS access entries for granting IAM identities access to
the Kubernetes API.

------------------------------------------------------------------------

# 4. Install tools on a Mac

Install AWS CLI:

``` bash
brew install awscli
```

Check:

``` bash
aws --version
```

Install kubectl:

``` bash
brew install kubectl
```

Check:

``` bash
kubectl version --client
```

Install eksctl:

``` bash
brew install eksctl
```

Check:

``` bash
eksctl version
```

Install Docker Desktop if it is not already installed. Docker is useful
for locally testing the image, although GitHub's hosted runner performs
the CI Docker build.

------------------------------------------------------------------------

# 5. Configure AWS on your Mac

For the initial infrastructure setup:

``` bash
aws configure
```

Enter credentials for an AWS identity that is allowed to create/manage
the resources needed for this lab.

Check the identity:

``` bash
aws sts get-caller-identity
```

This local setup is separate from GitHub Actions. The GitHub workflow
will use OIDC and short-lived credentials rather than storing a
permanent AWS access key in GitHub.

------------------------------------------------------------------------

# 6. Confirm/create the ECR repository

Check whether `mybookapi` exists:

``` bash
aws ecr describe-repositories \
  --repository-names mybookapi \
  --region eu-north-1
```

If it does not exist:

``` bash
aws ecr create-repository \
  --repository-name mybookapi \
  --region eu-north-1
```

The repository address for this lab is:

``` text
316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi
```

ECR stores the Docker images. EKS later pulls those images when it
creates Pods.

------------------------------------------------------------------------

# 7. Create the EKS cluster

For a simple training environment:

``` bash
eksctl create cluster \
  --name testbook-cluster \
  --region eu-north-1 \
  --nodegroup-name testbook-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --managed
```

Meaning:

-   `testbook-cluster` --- name of the Kubernetes cluster.
-   `eu-north-1` --- Stockholm AWS region.
-   `testbook-nodes` --- group of machines used to run Pods.
-   `t3.medium` --- EC2 size for the demo nodes.
-   `--nodes 2` --- start two worker machines.
-   `--managed` --- AWS manages the node group lifecycle.

Cluster creation can take several minutes and creates billable AWS
resources.

Check the cluster:

``` bash
aws eks describe-cluster \
  --name testbook-cluster \
  --region eu-north-1
```

------------------------------------------------------------------------

# 8. Connect your Mac to EKS

Run:

``` bash
aws eks update-kubeconfig \
  --region eu-north-1 \
  --name testbook-cluster
```

Then:

``` bash
kubectl get nodes
```

You want the nodes to show `Ready`.

Example:

``` text
NAME                         STATUS
ip-192-168-x-x               Ready
ip-192-168-x-x               Ready
```

If this command works, your Mac can talk to Kubernetes.

------------------------------------------------------------------------

# 9. Configure GitHub OIDC in AWS

OIDC lets GitHub prove its identity to AWS and receive temporary
credentials.

The simple idea is:

``` text
GitHub workflow
      |
      | OIDC identity token
      v
AWS IAM
      |
      | verifies repository/branch
      v
IAM Role
      |
      | temporary AWS credentials
      v
ECR + EKS
```

This avoids saving a permanent AWS Access Key and Secret Access Key in
GitHub.

In AWS IAM, confirm an OpenID Connect provider exists for:

``` text
token.actions.githubusercontent.com
```

The normal audience is:

``` text
sts.amazonaws.com
```

Your IAM role trust policy must restrict who can assume the role. For
this repository, restrict it to the appropriate GitHub repository/branch
identity. GitHub's OIDC subject format can depend on repository age and
organisation/repository identity settings, so use the subject value that
applies to your repository rather than blindly copying an example.

The workflow needs:

``` yaml
permissions:
  id-token: write
  contents: read
```

`id-token: write` only permits the workflow to request an OIDC identity
token. AWS permissions still come from the IAM role.

------------------------------------------------------------------------

# 10. IAM permissions needed by the GitHub role

Your existing role is:

``` text
arn:aws:iam::316255801172:role/GitHubActionsECRRole
```

For the demonstration, it needs permissions for two jobs:

## ECR

It must be able to authenticate and push the image to `mybookapi`.

Typical ECR actions include:

``` text
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:GetDownloadUrlForLayer
ecr:BatchGetImage
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:PutImage
```

For a production system, restrict permissions to the required repository
wherever AWS supports resource-level restriction.

## EKS

The role needs permission to discover the cluster, including:

``` text
eks:DescribeCluster
```

But AWS IAM permission alone is not enough for `kubectl`. The IAM role
also needs Kubernetes access to the cluster.

------------------------------------------------------------------------

# 11. Give the GitHub role access to EKS

AWS recommends EKS **access entries** for granting IAM identities
Kubernetes access.

First inspect the cluster:

``` bash
aws eks describe-cluster \
  --name testbook-cluster \
  --region eu-north-1 \
  --query 'cluster.accessConfig'
```

Create an EKS access entry for the GitHub role if one does not already
exist:

``` bash
aws eks create-access-entry \
  --cluster-name testbook-cluster \
  --principal-arn arn:aws:iam::316255801172:role/GitHubActionsECRRole \
  --type STANDARD \
  --region eu-north-1
```

For a simple training demonstration, you can associate the EKS
cluster-admin access policy:

``` bash
aws eks associate-access-policy \
  --cluster-name testbook-cluster \
  --principal-arn arn:aws:iam::316255801172:role/GitHubActionsECRRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region eu-north-1
```

**Important:** cluster-admin is intentionally broad and convenient for a
classroom demo. For a real project, give the GitHub deployment role only
the Kubernetes permissions it actually needs.

Check it:

``` bash
aws eks list-access-entries \
  --cluster-name testbook-cluster \
  --region eu-north-1
```

------------------------------------------------------------------------

# 12. Kubernetes Deployment file

Save `deployment.yaml` as:

``` text
kubernetes/deployment.yaml
```

The supplied file creates two application Pods.

Important parts:

``` yaml
replicas: 2
```

This means Kubernetes should keep two copies of the application running.

The container name is:

``` yaml
name: testbook-api
```

This name must match `K8S_CONTAINER` in the GitHub workflow.

The file deliberately contains:

``` yaml
image: IMAGE_PLACEHOLDER
```

The workflow replaces that placeholder during the first deployment with
the exact ECR image created by that Git commit.

The file also contains simple TCP readiness and liveness checks on port
8080. They do not depend on a Spring Actuator endpoint.

------------------------------------------------------------------------

# 13. Kubernetes Service file

Save `service.yaml` as:

``` text
kubernetes/service.yaml
```

It contains:

``` yaml
type: LoadBalancer
```

That asks AWS to provide an external load balancer.

The Service accepts traffic on port 80 and sends it to the application
on port 8080:

``` text
Internet
   |
   | port 80
   v
AWS Load Balancer
   |
   v
Kubernetes Service
   |
   | targetPort 8080
   v
TestBook API Pods
```

------------------------------------------------------------------------

# 14. Add the GitHub Actions workflow

Save:

``` text
03-eks-cicd.yml
```

as:

``` text
.github/workflows/03-eks-cicd.yml
```

The workflow can start in two ways.

Automatically:

``` yaml
push:
  branches:
    - main
```

Manually:

``` yaml
workflow_dispatch:
```

So you can demonstrate it without changing code:

**GitHub → repository → Actions → workflow → Run workflow**

------------------------------------------------------------------------

# 15. Understand the CI job

The first job is named:

``` text
CI - Test, Build and Push Image
```

It performs:

``` text
Checkout
   ↓
Java 17
   ↓
mvn clean verify
   ↓
AWS OIDC login
   ↓
ECR login
   ↓
docker build
   ↓
docker push
```

The Maven command is:

``` bash
mvn --batch-mode clean verify
```

If a test fails, this job fails and the CD job will not run.

That is an important CI/CD demonstration:

``` text
Bad code
   ↓
Test fails
   ↓
Pipeline stops
   X
No deployment
```

------------------------------------------------------------------------

# 16. Image versioning

The workflow uses:

``` text
${{ github.sha }}
```

as the image version.

For example:

``` text
mybookapi:53a31b7...
```

This connects a deployed Docker image to a specific Git commit.

It also publishes:

``` text
mybookapi:latest
```

for convenience.

The deployment itself uses the immutable Git-SHA image rather than
relying on `latest`.

------------------------------------------------------------------------

# 17. Understand the CD job

The CD job runs only after CI succeeds:

``` yaml
needs: ci
```

It then:

1.  Authenticates to AWS.
2.  Runs `aws eks update-kubeconfig`.
3.  Verifies access with `kubectl`.
4.  Applies the Kubernetes Service.
5.  Creates the Deployment on the first run.
6.  Updates the Deployment to the new image.
7.  Waits for the Kubernetes rollout.
8.  Displays the resources.

The important deployment command is effectively:

``` bash
kubectl set image \
  deployment/testbook-api \
  testbook-api=<new-ECR-image>
```

That tells Kubernetes:

> Keep the same application Deployment, but replace the application
> image with this new version.

------------------------------------------------------------------------

# 18. Commit everything

From the repository root:

``` bash
git add .
git status
```

You should see the three new/changed files in the correct directories.

Commit:

``` bash
git commit -m "Add EKS CI/CD pipeline"
```

Push:

``` bash
git push origin main
```

Because the workflow watches `main`, the pipeline should start
automatically.

------------------------------------------------------------------------

# 19. Watch the workflow

Open:

``` text
GitHub
→ testbookapiworkflowdemo
→ Actions
→ 03 - CI/CD - Build, Push to ECR and Deploy to EKS
```

You should first see the CI job.

If CI succeeds, CD starts.

The expected sequence is:

``` text
CI
✓ Checkout
✓ Java
✓ Maven tests/build
✓ AWS authentication
✓ ECR login
✓ Docker build
✓ Docker push

CD
✓ Checkout
✓ AWS authentication
✓ Connect to EKS
✓ Apply Service
✓ Create/update Deployment
✓ Wait for rollout
✓ Show resources
```

------------------------------------------------------------------------

# 20. Verify ECR

Run:

``` bash
aws ecr list-images \
  --repository-name mybookapi \
  --region eu-north-1
```

You should see the commit-based image tag and normally `latest`.

You can also inspect ECR in the AWS Console.

------------------------------------------------------------------------

# 21. Verify EKS

Check nodes:

``` bash
kubectl get nodes
```

Check Deployment:

``` bash
kubectl get deployment testbook-api
```

Check Pods:

``` bash
kubectl get pods
```

With `replicas: 2`, normally you should see two running application
Pods.

Check Service:

``` bash
kubectl get service testbook-service
```

Wait until an external hostname appears.

For more detail:

``` bash
kubectl describe service testbook-service
```

------------------------------------------------------------------------

# 22. Test the application

Get the hostname:

``` bash
kubectl get service testbook-service
```

You may see something similar to:

``` text
testbook-service   LoadBalancer   ...   xxxxx.elb.amazonaws.com
```

Use:

``` text
http://xxxxx.elb.amazonaws.com
```

plus the correct TestBook API endpoint.

The load balancer can take a short time to become ready after the
Service is first created.

------------------------------------------------------------------------

# 23. Demonstrate a real CI/CD change

Change something small in the application.

Then:

``` bash
git add .
git commit -m "Demo EKS deployment"
git push origin main
```

Explain this flow:

``` text
New commit
    ↓
Tests
    ↓
New Docker image
    ↓
ECR
    ↓
EKS Deployment updated
    ↓
Kubernetes starts new Pods
    ↓
Kubernetes removes old Pods
    ↓
New version is live
```

This is a rolling deployment.

------------------------------------------------------------------------

# 24. Demonstrate manual deployment

Because `workflow_dispatch` is enabled:

1.  Open the repository in GitHub.
2.  Click **Actions**.
3.  Select the EKS CI/CD workflow.
4.  Click **Run workflow**.
5.  Select `main`.
6.  Click **Run workflow**.

This rebuilds and redeploys the current commit.

------------------------------------------------------------------------

# 25. Demonstrate Kubernetes self-healing

List Pods:

``` bash
kubectl get pods
```

Copy one TestBook Pod name and delete it:

``` bash
kubectl delete pod <POD-NAME>
```

Immediately run:

``` bash
kubectl get pods
```

Because the Deployment requests two replicas, Kubernetes creates a
replacement Pod.

This is a good demonstration of the difference between simply running
Docker yourself and asking Kubernetes to maintain a desired state.

------------------------------------------------------------------------

# 26. Demonstrate scaling

Scale to four Pods:

``` bash
kubectl scale deployment testbook-api --replicas=4
```

Check:

``` bash
kubectl get pods
```

Return to two:

``` bash
kubectl scale deployment testbook-api --replicas=2
```

Note that a later full re-application of `deployment.yaml` can restore
the YAML-defined replica count.

------------------------------------------------------------------------

# 27. Check rollout history

Run:

``` bash
kubectl rollout history deployment/testbook-api
```

Check rollout status:

``` bash
kubectl rollout status deployment/testbook-api
```

------------------------------------------------------------------------

# 28. Roll back a deployment

If a new release has a problem:

``` bash
kubectl rollout undo deployment/testbook-api
```

Then:

``` bash
kubectl rollout status deployment/testbook-api
```

And:

``` bash
kubectl get pods
```

For a stronger production rollback process, record deployment revisions
and image versions deliberately rather than treating `latest` as the
source of truth.

------------------------------------------------------------------------

# 29. Useful troubleshooting commands

Pods:

``` bash
kubectl get pods -o wide
```

Deployment:

``` bash
kubectl describe deployment testbook-api
```

A particular Pod:

``` bash
kubectl describe pod <POD-NAME>
```

Application logs:

``` bash
kubectl logs <POD-NAME>
```

Follow logs:

``` bash
kubectl logs -f <POD-NAME>
```

Service:

``` bash
kubectl describe service testbook-service
```

Events:

``` bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

Current image:

``` bash
kubectl get deployment testbook-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

------------------------------------------------------------------------

# 30. Common error: GitHub can push to ECR but cannot use kubectl

Typical symptom:

``` text
Unauthorized
```

or Kubernetes says the GitHub role cannot perform an action.

Why?

There are two different permissions involved:

``` text
AWS IAM permission
        +
EKS/Kubernetes permission
```

Being allowed to call AWS/ECR does not automatically make the role a
Kubernetes administrator.

Check:

``` bash
aws eks list-access-entries \
  --cluster-name testbook-cluster \
  --region eu-north-1
```

Confirm the GitHub role appears and has the required EKS access policy.

------------------------------------------------------------------------

# 31. Common error: image cannot be pulled

Check:

``` bash
kubectl describe pod <POD-NAME>
```

Look for:

``` text
ImagePullBackOff
```

Confirm:

1.  The image exists in ECR.
2.  The image address is correct.
3.  Worker nodes can reach ECR.
4.  The EKS node role has the permissions needed to pull ECR images.

------------------------------------------------------------------------

# 32. Common error: application Pod keeps restarting

Check:

``` bash
kubectl get pods
```

Then:

``` bash
kubectl logs <POD-NAME>
```

And:

``` bash
kubectl describe pod <POD-NAME>
```

Possible causes include:

-   application startup failure,
-   wrong configuration,
-   port mismatch,
-   database/external dependency failure,
-   health checks failing.

For this lab, the Kubernetes file assumes the application listens on
`8080`.

------------------------------------------------------------------------

# 33. Common error: Load Balancer hostname is pending

Run:

``` bash
kubectl get service testbook-service
```

If the external address says `pending`, give AWS some time and check:

``` bash
kubectl describe service testbook-service
```

Also inspect:

``` bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

------------------------------------------------------------------------

# 34. Why there is no PEM file

The previous EC2 workflow looked like:

``` text
GitHub
   ↓ SSH + PEM
EC2
   ↓
docker run
```

The EKS workflow is:

``` text
GitHub
   ↓ OIDC
AWS
   ↓
EKS/Kubernetes API
   ↓
Deployment
   ↓
Pods
```

Therefore the deployment does not SSH into a worker node.

This is a useful point to emphasise during the demonstration.

------------------------------------------------------------------------

# 35. CI/CD architecture for the presentation

``` text
Developer
   |
   | git push
   v
GitHub Repository
   |
   v
GitHub Actions
   |
   +---------------- CI ----------------+
   |                                    |
   v                                    |
Maven Test                              |
   |                                    |
   v                                    |
Maven Build                             |
   |                                    |
   v                                    |
Docker Build                            |
   |                                    |
   v                                    |
Amazon ECR                              |
                                        |
   +---------------- CD ----------------+
   |
   v
Amazon EKS
   |
   v
Kubernetes Deployment
   |
   +-------------------+
   |                   |
   v                   v
Pod 1                 Pod 2
   \                   /
    \                 /
     v               v
      Kubernetes Service
             |
             v
       AWS Load Balancer
             |
             v
            User
```

------------------------------------------------------------------------

# 36. Cost warning and cleanup

EKS, EC2 worker nodes, load balancers, networking and ECR storage can
create AWS charges. Do not leave a training cluster running
unnecessarily.

If this cluster was created specifically by `eksctl` for the lab and you
no longer need anything in it, delete it with:

``` bash
eksctl delete cluster \
  --name testbook-cluster \
  --region eu-north-1
```

Confirm afterwards:

``` bash
aws eks list-clusters --region eu-north-1
```

Before deleting a real/shared environment, make sure nobody else is
using it and that nothing important depends on it.

You can separately inspect/delete unneeded ECR images if desired.

------------------------------------------------------------------------

# 37. Suggested live demo sequence

For a clean classroom demonstration:

1.  Show the Spring Boot source.
2.  Show `deployment.yaml`.
3.  Explain `replicas: 2`.
4.  Show `service.yaml`.
5.  Explain `LoadBalancer`, port `80`, target port `8080`.
6.  Show the GitHub Actions workflow.
7.  Explain the CI job.
8.  Explain the CD job.
9.  Push a small code change.
10. Watch Maven tests.
11. Show the new ECR image.
12. Watch the EKS rollout.
13. Run `kubectl get pods`.
14. Open the application through the load balancer.
15. Delete one Pod and show Kubernetes recreate it.
16. Scale the Deployment and show additional Pods.
17. Explain rollback.

That demonstrates CI, CD, Docker, ECR and Kubernetes without needing SSH
into the EKS worker nodes.

------------------------------------------------------------------------

# 38. Production improvements after the demo

The lab intentionally stays understandable. For a real production
system, consider:

-   separate development/staging/production environments,
-   least-privilege IAM and Kubernetes permissions,
-   protected GitHub environments and approvals,
-   dedicated deployment roles,
-   HTTPS and DNS,
-   proper Spring Boot readiness/liveness endpoints,
-   resource CPU/memory requests and limits,
-   secrets management,
-   autoscaling,
-   vulnerability scanning,
-   automated integration/API tests,
-   monitoring and alerts,
-   infrastructure as code,
-   GitOps/Argo CD if appropriate.

Do not add all of these to the first demo. The purpose of this lab is to
make the basic CI/CD path easy to understand first.
