# Testbook API demo — Helm commands explained

Use this from the `testbookapiworkflowdemo` folder on your Mac. Your Helm chart is `./helm/testbook-api`, the release is `testbook-api`, the namespace is `dev`, and the EKS cluster is `testbook-cluster` in `eu-north-1`.

**Copy each command as one line.** Do not insert `\` between arguments on the same line. Run the checks in order before installing. The example uses the ECR image tag `latest`, which you said worked; confirm that it still exists. Some commands require a healthy cluster and cannot be guaranteed to succeed without checking your live AWS setup.

## The short explanation

- **Chart**: the folder of instructions for building your Kubernetes objects.
- **Release**: the particular installation of that chart in your cluster.
- **Values**: settings such as image tag and number of copies of the app.
- **Revision**: a recorded version of a Helm release. Helm creates another revision when you upgrade or roll back.

## A. Check the folder, AWS account, and image

**1. `pwd`** — Shows your current folder. It should be the root of `testbookapiworkflowdemo`.

```bash
pwd
```

**2. `ls ...`** — Confirms that the chart and its main settings file exist. If it fails, change into the correct repository folder.

```bash
ls helm/testbook-api/Chart.yaml helm/testbook-api/values.yaml
```

**3. `helm version`** — Confirms Helm is installed and displays its version.

```bash
helm version
```

**4. `aws sts get-caller-identity`** — Shows the AWS account your terminal will use. For this demo, the account number should be `316255801172`.

```bash
aws sts get-caller-identity
```

**5. `aws eks update-kubeconfig ...`** — Adds or updates the connection details for `testbook-cluster` on your Mac. It does **not** create a cluster.

```bash
aws eks update-kubeconfig --region eu-north-1 --name testbook-cluster
```

**6. `kubectl config current-context`** — Displays the cluster currently selected by `kubectl`; check that it contains `testbook-cluster`.

```bash
kubectl config current-context
```

**7. `aws ecr list-images ...`** — Lists tags that actually exist in the `mybookapi` image repository. Confirm `latest` appears before installing.

```bash
aws ecr list-images --repository-name mybookapi --region eu-north-1 --filter tagStatus=TAGGED --query 'imageIds[].imageTag' --output table
```

If `latest` is absent, choose a listed tag and replace `latest` in the install command below. A tag that does not exist can cause `ErrImagePull`.

## B. Preview the chart

**8. `helm show values ...`** — Prints the chart's default settings, such as its default image tag and replica count. This command makes no cluster changes.

```bash
helm show values ./helm/testbook-api
```

**9. `helm lint ...`** — Checks the chart for common structural and template problems. Passing lint does not prove that the image can be pulled or the app can start.

```bash
helm lint ./helm/testbook-api
```

For a harmless failing example in class, lint a folder that does not exist. Helm reports that it cannot find a valid chart; it does not change your real chart:

```bash
helm lint ./helm/nonexistent-demo-chart
```

**10. `helm template ...`** — Shows the Kubernetes instructions that Helm would send to the cluster, without installing anything. The `--set` parts replace default settings for this preview.

```bash
helm template testbook-api ./helm/testbook-api --namespace dev --set image.repository=316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi --set image.tag=latest --set replicaCount=2 --set service.type=LoadBalancer
```

## C. Install or update the app

**11. `helm upgrade --install ...`** — Installs the release if it is missing; otherwise updates it. It uses the verified image, asks for two app copies, and sets up an AWS load balancer. `--create-namespace` makes `dev` if necessary; `--wait --timeout 5m` waits up to five minutes for readiness. This can create billable AWS resources.

```bash
helm upgrade --install testbook-api ./helm/testbook-api --namespace dev --create-namespace --set image.repository=316255801172.dkr.ecr.eu-north-1.amazonaws.com/mybookapi --set image.tag=latest --set replicaCount=2 --set service.type=LoadBalancer --wait --timeout 5m
```

There is **no** `-f ./helm/testbook-api/values-dev.yaml` here: that file was missing when you previously tried to use it. Helm requires two separate arguments after `upgrade`: the release name `testbook-api` and the chart path `./helm/testbook-api`.

**12. `helm list ...`** — Lists Helm releases installed in `dev`.

```bash
helm list --namespace dev
```

**13. `helm status ...`** — Shows the release state and resources Helm knows about. Use it immediately after install or when an upgrade fails.

```bash
helm status testbook-api --namespace dev
```

## D. Explain the installed settings and resources

**14. `helm get values ...`** — Shows the values that were supplied for this release, including your image and replica settings.

```bash
helm get values testbook-api --namespace dev
```

**15. `helm get values ... --all`** — Shows supplied values plus default values that Helm filled in.

```bash
helm get values testbook-api --namespace dev --all
```

**16. `helm get manifest ...`** — Displays the Kubernetes objects Helm installed, as text. Look for the Deployment and Service.

```bash
helm get manifest testbook-api --namespace dev
```

**17. `helm history ...`** — Displays the release's revision numbers. You need a known good revision for a rollback.

```bash
helm history testbook-api --namespace dev
```

## E. Demonstrate an upgrade and restore two copies

**18. `helm upgrade ... replicaCount=3`** — Records a new release revision asking for three app copies. `--reuse-values` keeps your current image and service settings. Three pods might not fit on two small nodes; inspect events if it times out.

```bash
helm upgrade testbook-api ./helm/testbook-api --namespace dev --reuse-values --set replicaCount=3 --wait --timeout 5m
```

**19. `helm get values ...`** — Show the audience that the requested count is now three.

```bash
helm get values testbook-api --namespace dev
```

**20. `helm history ...`** — Show that Helm added a revision for the change.

```bash
helm history testbook-api --namespace dev
```

**21. `helm upgrade ... replicaCount=2`** — Return to two copies using a new Helm revision. This is also the recovery step if the third pod cannot be scheduled.

```bash
helm upgrade testbook-api ./helm/testbook-api --namespace dev --reuse-values --set replicaCount=2 --wait --timeout 5m
```

Changing the number of copies directly with `kubectl scale` is quicker, but a later Helm upgrade can restore the count in Helm's saved settings. The companion `kubectl` sheet includes that demonstration.

## F. Roll back, if an upgrade goes wrong

**22. `helm history ...`** — Find the exact revision that was working.

```bash
helm history testbook-api --namespace dev
```

**23. `helm rollback ...`** — Replace `REVISION_NUMBER` with the number you just saw. This restores that release version and waits up to five minutes. Do not paste the word `REVISION_NUMBER` unchanged.

```bash
helm rollback testbook-api REVISION_NUMBER --namespace dev --wait --timeout 5m
```

**24. `helm status ...`** — Check the result of the rollback.

```bash
helm status testbook-api --namespace dev
```

## G. Remove the release when your demo is finished

**25. `helm uninstall ...`** — Removes this Helm release and its chart-managed objects, including its Service. This interrupts the app and starts removal of its AWS load balancer. Run only when you are finished with this release.

```bash
helm uninstall testbook-api --namespace dev
```

**26. `kubectl get service ...`** — Check whether the Service was removed. If it says `NotFound` after uninstall, that is the expected result.

```bash
kubectl get service testbook-api --namespace dev
```

Uninstalling a Helm release does **not** delete the EKS cluster or its two EC2 nodes. They can keep costing money. Delete the entire cluster separately only when you no longer need it.

## Errors you already met

| Error | Meaning | What to do |
| --- | --- | --- |
| `helm upgrade requires 2 arguments` | The backslashes and spaces on one line broke the release and chart arguments. | Copy the one-line command in step 11. |
| `values-dev.yaml: no such file or directory` | That optional file is missing. | Use step 11 without `-f`. |
| `ErrImagePull` | Kubernetes could not obtain the requested image. | Verify the ECR tag in step 7; use the `kubectl` sheet to inspect pod events. |
| `--wait` timeout | One or more resources were not ready within five minutes. | Check `helm status`, pods, deployment, service, and events. |

**Official references:** [Helm upgrade](https://helm.sh/docs/helm/helm_upgrade/), [Helm lint](https://helm.sh/docs/helm/helm_lint/), [Helm rollback](https://helm.sh/docs/helm/helm_rollback/).
