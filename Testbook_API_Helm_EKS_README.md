# Testbook API --- Helm + GitHub Actions + Amazon ECR + Amazon EKS Demo

## 1. What are we demonstrating?

This demo takes the existing Testbook API CI/CD flow:

``` text
Developer
   |
   v
GitHub repository
   |
   v
GitHub Actions
   |
   +---- Maven build and automated tests
   |
   +---- Docker build
   |
   v
Amazon ECR
   |
   | Docker image
   v
Helm
   |
   | Creates/updates Kubernetes resources
   v
Amazon EKS
   |
   +---- Deployment
   |       |
   |       +---- Pod / Testbook API
   |       +---- Pod / Testbook API
   |
   +---- Service
```

The important change is that **Helm becomes responsible for packaging
and deploying the Kubernetes configuration**.

Previously we might have run commands such as:

``` bash
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml
```

With Helm, GitHub Actions can instead run one deployment command:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api
```

------------------------------------------------------------------------

# 2. Helm explained in simple terms

Think about installing an application on your phone.

You normally do not manually create every file that the application
needs. You install one package and the installer knows what needs to be
created.

Helm provides a similar idea for Kubernetes.

A **Helm Chart** is a package containing instructions for deploying an
application to Kubernetes.

For Testbook API, the chart can contain instructions for:

-   how many copies of Testbook API should run;
-   which Docker image should be used;
-   which port the application uses;
-   how Kubernetes should expose the application;
-   CPU/memory settings if required;
-   environment-specific settings.

------------------------------------------------------------------------

# 3. Why use Helm if Kubernetes YAML already works?

Suppose our Kubernetes Deployment contains:

``` yaml
replicas: 2
```

and:

``` yaml
image: 316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:abc1234
```

Without Helm, these values may be directly written into Kubernetes YAML
files.

Helm allows us to turn them into configurable values.

For example:

``` yaml
replicaCount: 2

image:
  repository: 316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi
  tag: latest
```

The Kubernetes template then says:

``` yaml
replicas: {{ .Values.replicaCount }}
```

and:

``` yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

This means the **structure stays the same while the values can change**.

That is especially useful in CI/CD.

GitHub Actions creates a new Docker image on every deployment. Instead
of editing `deployment.yaml`, the workflow simply tells Helm:

``` bash
--set image.tag=NEW_IMAGE_TAG
```

------------------------------------------------------------------------

# 4. Our Testbook API use case

Assume a developer pushes a change to GitHub.

### CI portion

GitHub Actions:

1.  downloads the Testbook API source code;
2.  installs Java;
3.  runs Maven build and tests;
4.  authenticates with AWS;
5.  builds a Docker image;
6.  tags the image using the Git commit;
7.  pushes the image into Amazon ECR.

Example:

``` text
316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:a1b2c3d
```

### CD portion

GitHub Actions then:

1.  connects to `testbook-cluster`;
2.  installs Helm on the GitHub runner;
3.  validates the Helm chart;
4.  gives Helm the new ECR image;
5.  Helm generates the Kubernetes configuration;
6.  Helm deploys it to EKS;
7.  Kubernetes starts/replaces the Testbook API Pods;
8.  GitHub Actions verifies that the deployment completed.

So the deployment path becomes:

``` text
Source code
    |
    v
GitHub Actions
    |
    +--> Maven test
    |
    +--> Docker build
    |
    v
Amazon ECR
    |
    | new image
    v
Helm Chart + image tag
    |
    v
Amazon EKS
    |
    v
Testbook API Pods
```

------------------------------------------------------------------------

# 5. Recommended repository structure

Create this structure inside your existing repository:

``` text
testbookapiworkflowdemo/
|
+-- .github/
|   +-- workflows/
|       +-- ci-cd-eks-helm.yml
|
+-- helm/
|   +-- testbook-api/
|       +-- Chart.yaml
|       +-- values.yaml
|       +-- templates/
|           +-- deployment.yaml
|           +-- service.yaml
|
+-- src/
|
+-- Dockerfile
+-- pom.xml
+-- README.md
```

------------------------------------------------------------------------

# 6. Create the Helm chart

From the root of the repository you can initially run:

``` bash
mkdir -p helm
helm create helm/testbook-api
```

`helm create` creates example files. For this demo, you can simplify the
chart and keep the files shown below.

------------------------------------------------------------------------

# 7. Create `Chart.yaml`

File:

``` text
helm/testbook-api/Chart.yaml
```

Content:

``` yaml
apiVersion: v2
name: testbook-api
description: Helm chart for deploying Testbook API to Amazon EKS
type: application
version: 0.1.0
appVersion: "1.0"
```

## What does this file mean?

`name` is the name of the Helm chart.

`version` is the version of the **chart itself**.

`appVersion` describes the application version for human reference. In
this demo the actual Docker image version is supplied by GitHub Actions.

------------------------------------------------------------------------

# 8. Create `values.yaml`

File:

``` text
helm/testbook-api/values.yaml
```

Content:

``` yaml
replicaCount: 2

image:
  repository: 316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi
  tag: latest
  pullPolicy: IfNotPresent

container:
  port: 8080

service:
  type: LoadBalancer
  port: 80
  targetPort: 8080
```

This is one of the most important Helm files.

Think of `values.yaml` as the **settings page** for the application.

Instead of changing the Kubernetes templates every time, we normally
change values here or override them from the deployment command.

For example:

``` yaml
replicaCount: 2
```

could later become:

``` yaml
replicaCount: 5
```

without changing the Deployment template.

------------------------------------------------------------------------

# 9. Create the Deployment template

File:

``` text
helm/testbook-api/templates/deployment.yaml
```

Content:

``` yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: testbook-api
  labels:
    app: testbook-api

spec:
  replicas: {{ .Values.replicaCount }}

  selector:
    matchLabels:
      app: testbook-api

  template:
    metadata:
      labels:
        app: testbook-api

    spec:
      containers:
        - name: testbook-api

          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"

          imagePullPolicy: {{ .Values.image.pullPolicy }}

          ports:
            - name: http
              containerPort: {{ .Values.container.port }}
              protocol: TCP
```

Notice the special expressions:

``` text
{{ .Values.replicaCount }}
```

and:

``` text
{{ .Values.image.repository }}
{{ .Values.image.tag }}
```

Helm replaces these placeholders with real values before sending the
configuration to Kubernetes.

For example, Helm could turn:

``` yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

into:

``` yaml
image: "316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:a1b2c3d"
```

------------------------------------------------------------------------

# 10. Create the Service template

File:

``` text
helm/testbook-api/templates/service.yaml
```

Content:

``` yaml
apiVersion: v1
kind: Service

metadata:
  name: testbook-api
  labels:
    app: testbook-api

spec:
  type: {{ .Values.service.type }}

  selector:
    app: testbook-api

  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
```

The Deployment runs the application.

The Service gives Kubernetes a stable way of reaching the application.

Because this example uses:

``` yaml
type: LoadBalancer
```

AWS can create an external load balancer for the service.

For a short demo, remember that creating an AWS load balancer can take a
little time and can incur AWS charges.

------------------------------------------------------------------------

# 11. Validate the chart locally

Install Helm on your Mac if it is not installed:

``` bash
brew install helm
```

Check it:

``` bash
helm version
```

Now run:

``` bash
helm lint ./helm/testbook-api
```

`helm lint` checks the chart for common mistakes.

Expected result should contain something similar to:

``` text
1 chart(s) linted, 0 chart(s) failed
```

------------------------------------------------------------------------

# 12. See what Helm will generate without deploying

This is an excellent command for the classroom/demo:

``` bash
helm template testbook-api ./helm/testbook-api
```

Helm reads:

``` text
Chart.yaml
      +
values.yaml
      +
templates/
```

and produces normal Kubernetes YAML.

Nothing is deployed by this command.

This makes it easy to explain that **Kubernetes itself does not need to
understand Helm templates**. Helm first converts the templates into
normal Kubernetes configuration.

------------------------------------------------------------------------

# 13. Test Helm manually against EKS

First connect `kubectl` to the cluster:

``` bash
aws eks update-kubeconfig \
  --region eu-north-1 \
  --name testbook-cluster
```

Check the connection:

``` bash
kubectl get nodes
```

Then perform a manual Helm deployment:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api \
  --set image.repository=316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi \
  --set image.tag=YOUR_EXISTING_ECR_IMAGE_TAG \
  --wait
```

If ECR currently contains no image, do not run this manual deployment
yet. Let GitHub Actions build and push the first image.

------------------------------------------------------------------------

# 14. Why use `helm upgrade --install`?

This command is very useful in CI/CD:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api
```

It effectively means:

``` text
Does testbook-api already exist?

NO
 |
 +--> Install it

YES
 |
 +--> Upgrade it
```

Therefore the same GitHub Actions workflow can be used for the first
deployment and future deployments.

------------------------------------------------------------------------

# 15. Add the GitHub Actions workflow

Create:

``` text
.github/workflows/ci-cd-eks-helm.yml
```

Use the workflow supplied with this demo.

The important Helm deployment command in that workflow is:

``` bash
helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
  --namespace "$K8S_NAMESPACE" \
  --set image.repository="${IMAGE_REPOSITORY}" \
  --set image.tag="${IMAGE_TAG}" \
  --wait \
  --atomic \
  --timeout 5m
```

The workflow file uses GitHub job outputs to pass `IMAGE_REPOSITORY` and
`IMAGE_TAG` from CI to CD.

------------------------------------------------------------------------

# 16. What exactly happens to the image tag?

Suppose the Git commit is:

``` text
abc123456789
```

The workflow uses the first seven characters:

``` text
abc1234
```

The CI job builds:

``` text
316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:abc1234
```

and pushes it to ECR.

The CD job then effectively runs:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api \
  --set image.repository=316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi \
  --set image.tag=abc1234
```

Helm renders the Deployment with:

``` yaml
image: 316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:abc1234
```

Kubernetes sees that the Deployment now points to a new image and
performs the rollout.

------------------------------------------------------------------------

# 17. AWS/GitHub authentication requirement

The workflow uses GitHub OIDC.

That means GitHub Actions asks AWS for temporary credentials rather than
keeping a permanent AWS access key and secret key in GitHub.

The workflow therefore needs:

``` yaml
permissions:
  id-token: write
  contents: read
```

and:

``` yaml
- name: Configure AWS credentials using GitHub OIDC
  uses: aws-actions/configure-aws-credentials@v6.3.0
  with:
    role-to-assume: arn:aws:iam::316255801172:role/GitHubActionsECRRole
    aws-region: eu-north-1
```

Your IAM role must have permission to perform the ECR operations and the
required EKS access.

Your existing GitHub-to-AWS OIDC setup can therefore be reused.

------------------------------------------------------------------------

# 18. Important EKS access point

AWS authentication and Kubernetes authorization are related but separate
ideas.

The GitHub IAM role may successfully log in to AWS but still fail when
running:

``` bash
kubectl get nodes
```

if the role has not been given appropriate access to the EKS cluster.

Because your previous EKS GitHub Actions demo already used the same
role, you should normally be able to reuse that setup.

Test it by checking whether this workflow step succeeds:

``` bash
kubectl get nodes
```

------------------------------------------------------------------------

# 19. Run the demo

Commit the new Helm chart and workflow:

``` bash
git add .
git commit -m "Add Helm deployment to EKS"
git push origin main
```

Then open:

``` text
GitHub
  -> testbookapiworkflowdemo
  -> Actions
  -> Testbook API - CI/CD with Helm and Amazon EKS
```

You can also use:

``` text
Actions
  -> workflow
  -> Run workflow
```

because the workflow includes:

``` yaml
workflow_dispatch:
```

------------------------------------------------------------------------

# 20. What to show during the live demo

A good demonstration sequence is:

### Demo 1 --- Show the chart

Show:

``` text
helm/testbook-api/
```

Explain:

``` text
Chart.yaml
```

= information about the package.

``` text
values.yaml
```

= settings/configuration.

``` text
templates/
```

= reusable Kubernetes templates.

------------------------------------------------------------------------

### Demo 2 --- Show the values

Open:

``` text
values.yaml
```

Point out:

``` yaml
replicaCount: 2
```

Explain that the same template could deploy 2, 3, 5, or more Pods simply
by changing a value.

------------------------------------------------------------------------

### Demo 3 --- Render locally

Run:

``` bash
helm template testbook-api ./helm/testbook-api
```

Show that Helm converts the template into normal Kubernetes YAML.

------------------------------------------------------------------------

### Demo 4 --- Run GitHub Actions

Push a code change or manually start the workflow.

Show these stages:

``` text
Maven
  |
Docker
  |
ECR
  |
Helm
  |
EKS
```

------------------------------------------------------------------------

### Demo 5 --- Show the Helm release

After deployment:

``` bash
helm list
```

Then:

``` bash
helm status testbook-api
```

You can also run:

``` bash
helm history testbook-api
```

This is an important advantage over simply thinking in terms of
individual YAML files: Helm keeps release revisions.

------------------------------------------------------------------------

# 21. Demonstrate an upgrade

Change:

``` yaml
replicaCount: 2
```

to:

``` yaml
replicaCount: 3
```

Commit and push:

``` bash
git add .
git commit -m "Scale Testbook API to three replicas"
git push origin main
```

The workflow runs again.

Then check:

``` bash
kubectl get pods
```

You should now see three Testbook API Pods once the rollout completes.

Check Helm history:

``` bash
helm history testbook-api
```

You should see another Helm revision.

------------------------------------------------------------------------

# 22. Demonstrate rollback

First see the revisions:

``` bash
helm history testbook-api
```

Example:

``` text
REVISION
1
2
```

To return to revision 1:

``` bash
helm rollback testbook-api 1
```

Then verify:

``` bash
helm status testbook-api
kubectl get pods
```

This is a useful Helm feature to demonstrate because Helm treats the
deployment as a release with revision history.

------------------------------------------------------------------------

# 23. Useful Helm commands for the demo

Check Helm:

``` bash
helm version
```

Validate the chart:

``` bash
helm lint ./helm/testbook-api
```

Render without deployment:

``` bash
helm template testbook-api ./helm/testbook-api
```

Install:

``` bash
helm install testbook-api ./helm/testbook-api
```

Install or upgrade:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api
```

List releases:

``` bash
helm list
```

Check release:

``` bash
helm status testbook-api
```

See history:

``` bash
helm history testbook-api
```

Rollback:

``` bash
helm rollback testbook-api 1
```

Remove the release:

``` bash
helm uninstall testbook-api
```

------------------------------------------------------------------------

# 24. Helm vs plain Kubernetes YAML

## Plain Kubernetes approach

You may have:

``` text
deployment.yaml
service.yaml
configmap.yaml
```

and run:

``` bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f configmap.yaml
```

This works and is perfectly reasonable for simple deployments.

The difficulty grows when you have different environments or frequently
changing values.

For example:

``` text
DEV       -> replicas 1
TEST      -> replicas 2
PROD      -> replicas 5
```

or different image tags and settings.

You can end up maintaining several almost-identical YAML files.

## Helm approach

Keep common templates:

``` text
templates/
  deployment.yaml
  service.yaml
```

and supply different settings.

For example:

``` text
values-dev.yaml
values-test.yaml
values-prod.yaml
```

Then:

``` bash
helm upgrade --install testbook-api ./helm/testbook-api \
  -f values-prod.yaml
```

This reduces duplicated configuration.

------------------------------------------------------------------------

# 25. Where Helm sits in the architecture

Helm does **not** replace Docker.

Helm does **not** replace ECR.

Helm does **not** replace Kubernetes/EKS.

Helm does **not** replace GitHub Actions.

Each has a different job:

``` text
GitHub
   |
   | stores code
   v
GitHub Actions
   |
   | automates CI/CD
   v
Docker
   |
   | packages the Java application
   v
Amazon ECR
   |
   | stores Docker images
   v
Helm
   |
   | packages/configures the Kubernetes deployment
   v
Amazon EKS
   |
   | runs Kubernetes
   v
Pods
   |
   | run Testbook API containers
   v
Service / Load Balancer
   |
   v
Users
```

------------------------------------------------------------------------

# 26. Docker image vs Helm chart

This distinction is important.

## Docker image

Contains the **application**.

For example:

``` text
Java
Spring Boot
application JAR
libraries
```

Think:

> What should run?

## Helm chart

Contains the **deployment instructions**.

For example:

``` text
Run two copies.
Use this Docker image.
Expose port 8080.
Create a LoadBalancer service.
```

Think:

> How should it run inside Kubernetes?

------------------------------------------------------------------------

# 27. `values.yaml` vs GitHub Actions

Another useful distinction:

`values.yaml` contains sensible default deployment settings.

GitHub Actions knows information that exists only during the current
pipeline run, especially the newly created Docker image tag.

Therefore this workflow uses:

``` bash
--set image.repository=...
--set image.tag=...
```

Those values override the defaults from `values.yaml`.

This gives us:

``` text
Reusable Helm chart
       +
default values
       +
current CI/CD image tag
       |
       v
final Kubernetes configuration
```

------------------------------------------------------------------------

# 28. Why `helm lint`?

The workflow runs:

``` bash
helm lint "$HELM_CHART_PATH"
```

before deployment.

This catches common chart problems early.

In simple terms:

``` text
Deploy immediately
       X

Check chart
   |
   v
Deploy
       ✓
```

------------------------------------------------------------------------

# 29. Why `helm template` in the workflow?

The workflow also runs:

``` bash
helm template ...
```

This is not strictly required to deploy.

It is included because it is excellent for a demonstration.

It lets you show the audience:

> Here is our Helm template, and here is the normal Kubernetes YAML Helm
> generated from it.

------------------------------------------------------------------------

# 30. Why `--wait`?

The deployment command contains:

``` bash
--wait
```

Without it, Helm can submit the resources and finish while Kubernetes is
still starting the application.

With `--wait`, the pipeline waits for the resources to become ready,
subject to the timeout.

This makes the CI/CD result more meaningful.

------------------------------------------------------------------------

# 31. Why `--atomic`?

The command also contains:

``` bash
--atomic
```

For an upgrade, if the new deployment cannot complete successfully, Helm
can roll back the failed upgrade instead of simply leaving that failed
release as the active upgrade.

This is particularly useful for demonstrating safer automated
deployments.

------------------------------------------------------------------------

# 32. What happens on the very first run?

Initially:

``` text
ECR repository = exists
Docker image    = may be empty
Helm release    = does not exist
```

The workflow:

``` text
Build Java application
        |
        v
Build Docker image
        |
        v
Push first image to ECR
        |
        v
helm upgrade --install
        |
        v
Helm sees no existing release
        |
        v
INSTALL
        |
        v
EKS downloads image
        |
        v
Pods start
```

Therefore you do **not** need to manually push an image to ECR before
running this complete pipeline, provided the CI job succeeds and has
permission to push to ECR.

------------------------------------------------------------------------

# 33. What happens on the second run?

The second code change creates another image.

Example:

``` text
First run:
mybookapi:abc1234

Second run:
mybookapi:def5678
```

GitHub Actions gives Helm:

``` text
image.tag=def5678
```

Helm detects that `testbook-api` already exists.

Because the command is:

``` bash
helm upgrade --install
```

Helm performs an upgrade.

Kubernetes then rolls the Pods over to the new image.

------------------------------------------------------------------------

# 34. Check the deployed image

Run:

``` bash
kubectl get deployment testbook-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

This should display something similar to:

``` text
316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi:abc1234
```

This is a strong end-to-end proof that the image built by GitHub Actions
reached EKS.

------------------------------------------------------------------------

# 35. Find the application URL

Run:

``` bash
kubectl get service testbook-api
```

For a LoadBalancer service, look at:

``` text
EXTERNAL-IP
```

On AWS this may appear as a load-balancer DNS name rather than a numeric
IP address.

It can initially show:

``` text
<pending>
```

while AWS is creating the load balancer.

Once available, test the appropriate Testbook API endpoint.

------------------------------------------------------------------------

# 36. Clean up after the demo

Remove the Helm application:

``` bash
helm uninstall testbook-api
```

Check:

``` bash
helm list
```

If the EKS cluster itself is only for demonstrations and is no longer
needed, delete it separately using your normal EKS cleanup process.

Remember that EKS worker resources and AWS load balancers can generate
charges while they exist.

------------------------------------------------------------------------

# 37. One-minute explanation for your audience

You can explain the entire demo like this:

> GitHub Actions first performs CI. It builds and tests our Testbook
> API, creates a Docker image, and pushes that image to Amazon ECR.
>
> For CD, instead of directly maintaining and applying multiple
> Kubernetes YAML files, we use a Helm chart. The Helm chart contains
> reusable templates for our Kubernetes Deployment and Service.
>
> GitHub Actions passes the newly generated Docker image tag to Helm.
> Helm combines that value with our templates and generates the final
> Kubernetes configuration.
>
> Helm then installs or upgrades the Testbook API release on Amazon EKS.
> Kubernetes starts the required Pods using the new Docker image.
>
> This makes the Kubernetes deployment easier to configure, reuse,
> upgrade and roll back.

------------------------------------------------------------------------

# 38. Final mental model

Remember these five lines:

``` text
Docker       = package my application
ECR          = store my Docker image
Kubernetes   = run my containers
Helm         = package/manage my Kubernetes configuration
GitHub Actions = automate the whole journey
```

And for this Testbook API:

``` text
git push
   |
   v
GitHub Actions
   |
   +--> Maven build/test
   |
   +--> Docker build
   |
   +--> ECR push
   |
   +--> Helm lint/template
   |
   +--> Helm upgrade --install
   |
   v
Amazon EKS
   |
   v
Testbook API
```
