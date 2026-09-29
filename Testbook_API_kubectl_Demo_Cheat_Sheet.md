# Testbook API demo — kubectl commands explained

Use this with the [Helm demo sheet](Testbook_API_Helm_Demo_Cheat_Sheet.md). Your cluster is `testbook-cluster` in `eu-north-1`; the app is in namespace `dev`. Install it with Helm first, then use these commands to show what Kubernetes actually runs.

**Copy each command on one line.** `--namespace dev` means “look inside the dev group.” A **node** is a computer in the cluster; a **pod** is a running copy of the app. Two app copies do not mean two nodes, and Kubernetes can place more than one pod on a node when there is capacity.

## A. Confirm the cluster connection

**1. `aws eks update-kubeconfig ...`** — Sets up your Mac's connection to the named EKS cluster. It does not create the cluster.

```bash
aws eks update-kubeconfig --region eu-north-1 --name testbook-cluster
```

**2. `kubectl version --client`** — Shows that the `kubectl` command is installed locally.

```bash
kubectl version --client
```

**3. `kubectl config current-context`** — Displays the cluster currently selected. Confirm that the name contains `testbook-cluster` before changing anything.

```bash
kubectl config current-context
```

**4. `kubectl cluster-info`** — Checks that the cluster can be reached and shows its control-plane address.

```bash
kubectl cluster-info
```

## B. Show the nodes and the app

**5. `kubectl get nodes ...`** — Lists the computers running your pods and their EC2 sizes. Your previous result had two `t3.small` nodes.

```bash
kubectl get nodes -L node.kubernetes.io/instance-type
```

**6. `kubectl get nodes -o wide`** — Shows extra node details, including internal addresses and versions.

```bash
kubectl get nodes -o wide
```

**7. `kubectl get namespaces`** — Lists groups inside the cluster. Confirm `dev` exists.

```bash
kubectl get namespaces
```

**8. `kubectl get all ...`** — Gives a quick view of common app objects, including pods, Deployment and Service. Despite its name, it does not show literally every resource type.

```bash
kubectl get all --namespace dev
```

**9. `kubectl get deployment ...`** — Shows requested, available, and ready app copies. The Deployment keeps the desired number running.

```bash
kubectl get deployment testbook-api --namespace dev
```

**10. `kubectl get pods ... -o wide`** — Shows each app pod and the node on which it is running. Use this to answer “which node runs which pod?”

```bash
kubectl get pods --namespace dev -o wide
```

**11. `kubectl get service ...`** — Shows how traffic reaches the app. For `LoadBalancer`, the external hostname may initially display `pending` while AWS prepares it.

```bash
kubectl get service testbook-api --namespace dev -o wide
```

**12. `kubectl get endpointslice ...`** — Shows addresses of ready pod backends attached to Services. This helps explain how the Service finds the app.

```bash
kubectl get endpointslice --namespace dev
```

## C. Demonstrate scaling and readiness

**13. `kubectl scale ... --replicas=3`** — Requests three app pods immediately. This changes pods, not the number of EC2 nodes. Use this exact one-line format: `\ --replicas=3 \ -n dev` on one line caused your earlier “replicas not set” error.

```bash
kubectl scale deployment/testbook-api --replicas=3 --namespace dev
```

**14. `kubectl rollout status ...`** — Waits up to five minutes for the Deployment to finish making the change. If a pod cannot start, it can time out; inspect events below.

```bash
kubectl rollout status deployment/testbook-api --namespace dev --timeout=5m
```

**15. `kubectl get pods ... -o wide`** — Shows three pods and the nodes assigned to them. A third pod can stay `Pending` if the nodes lack spare capacity.

```bash
kubectl get pods --namespace dev -o wide
```

**16. `kubectl scale ... --replicas=2`** — Puts the demo back to its original two pods.

```bash
kubectl scale deployment/testbook-api --replicas=2 --namespace dev
```

**17. `kubectl rollout status ...`** — Confirms the return to two ready pods.

```bash
kubectl rollout status deployment/testbook-api --namespace dev --timeout=5m
```

Helm may set the replica count back to the value in its saved release during a later upgrade. To record scaling as a Helm release change, use the Helm sheet's `helm upgrade --reuse-values --set replicaCount=...` commands.

## D. Show automatic pod replacement

**18. `kubectl get pods ...`** — Copy the name of a pod in `dev`. Choose one belonging to `testbook-api`.

```bash
kubectl get pods --namespace dev -o wide
```

**19. `kubectl delete pod ...`** — Replace `ACTUAL_POD_NAME` with the name you copied. Deleting a pod interrupts that copy of the app; the Deployment normally makes a replacement. Do not paste the literal words `ACTUAL_POD_NAME`.

```bash
kubectl delete pod ACTUAL_POD_NAME --namespace dev
```

**20. `kubectl get pods ... -w`** — Watches the old pod disappear and a new one appear. Press **Ctrl-C** to stop watching.

```bash
kubectl get pods --namespace dev -w
```

**21. `kubectl rollout status ...`** — Confirms the replacement is ready before moving on.

```bash
kubectl rollout status deployment/testbook-api --namespace dev --timeout=5m
```

## E. Investigate a problem in front of the audience

**22. `kubectl describe deployment ...`** — Gives detailed information about the requested image, replica counts and recent Deployment events.

```bash
kubectl describe deployment testbook-api --namespace dev
```

**23. `kubectl get events ...`** — Displays recent activity in time order. Look for image pull problems, failed scheduling, or containers repeatedly starting.

```bash
kubectl get events --namespace dev --sort-by=.metadata.creationTimestamp
```

**24. `kubectl describe pod ...`** — Replace `ACTUAL_POD_NAME` with a pod from step 10. The Events section near the bottom often explains `ErrImagePull` or `Pending`.

```bash
kubectl describe pod ACTUAL_POD_NAME --namespace dev
```

**25. `kubectl logs deployment/...`** — Shows the latest 100 lines printed by one selected pod in the Deployment. Useful for app startup errors.

```bash
kubectl logs deployment/testbook-api --namespace dev --tail=100
```

**26. `kubectl logs -f ...`** — Keeps showing new lines as the application prints them. Press **Ctrl-C** to stop.

```bash
kubectl logs -f deployment/testbook-api --namespace dev --tail=50
```

**27. `kubectl logs ... --previous`** — Replace `ACTUAL_POD_NAME`. Shows logs from the previous container in a pod that restarted. It may say there is no previous container if no restart occurred.

```bash
kubectl logs ACTUAL_POD_NAME --namespace dev --previous --tail=100
```

**28. `kubectl rollout history ...`** — Shows Kubernetes' history of Deployment changes. This is different from `helm history`, which records Helm release changes.

```bash
kubectl rollout history deployment/testbook-api --namespace dev
```

| Pod status | Simple meaning | Start with |
| --- | --- | --- |
| `ErrImagePull` or `ImagePullBackOff` | The image cannot be downloaded. | `kubectl describe pod ...`; check ECR tag and node access. |
| `Pending` | A node has not been assigned or cannot accommodate it. | `kubectl describe pod ...`; inspect the scheduling Events. |
| `CrashLoopBackOff` | The app starts but repeatedly exits. | Current and `--previous` logs. |
| `Running` but not ready | The process runs but has not passed its readiness check. | `describe pod`, logs and the app's readiness route. |

## F. Access the app

**29. `kubectl describe service ...`** — Shows Service ports, the AWS hostname if assigned, and addresses of pods receiving traffic.

```bash
kubectl describe service testbook-api --namespace dev
```

**30. `kubectl port-forward ...`** — Lets your Mac reach Service port 80 at `localhost:18080`. Keep this terminal open and press **Ctrl-C** when finished. This assumes the chart exposes Service port 80, as in your earlier Service output.

```bash
kubectl port-forward --namespace dev service/testbook-api 18080:80
```

**31. `curl ...`** — In a **second terminal**, requests the root route through the port-forward. Replace `/` with a route you know the app supports if `/` returns 404; 404 alone does not mean Kubernetes failed.

```bash
curl -i http://localhost:18080/
```

You can also open the external hostname shown in step 11 in a browser. It must have finished provisioning, and network rules must allow access.

## G. Optional: show resource usage

**32. `kubectl top nodes`** — Shows CPU and memory use of the cluster computers. Works only if Metrics Server is installed; skip if the command reports that metrics are unavailable.

```bash
kubectl top nodes
```

**33. `kubectl top pods ...`** — Shows CPU and memory use of pods in `dev`. It has the same Metrics Server requirement.

```bash
kubectl top pods --namespace dev
```

## H. Verify cleanup after Helm uninstall

**34. `kubectl get all ...`** — After running `helm uninstall testbook-api --namespace dev` from the Helm sheet, check that the chart-managed app resources have disappeared. The cluster itself remains.

```bash
kubectl get all --namespace dev
```

### Suggested order for your live demonstration

1. **Connection:** commands 1–4.
2. **What is running:** commands 5–12.
3. **Scaling:** commands 13–17.
4. **Recovery:** commands 18–21.
5. **Diagnosis and access:** commands 22–31.

**Official references:** [kubectl command reference](https://kubernetes.io/docs/reference/kubectl/), [scale](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/), [rollout](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/), [logs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/), [port-forward](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/).
