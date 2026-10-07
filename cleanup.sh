kubectl delete application testbook-api -n argocd --ignore-not-found=true; \
helm uninstall testbook-api -n dev 2>/dev/null || true; \
kubectl delete namespace dev --ignore-not-found=true; \
echo "Deleting EKS cluster..."; \
eksctl delete cluster --name testbook-cluster --region eu-north-1 --wait; \
echo "===== CLEANUP COMPLETE ====="; \
echo "Remaining EKS clusters:"; \
aws eks list-clusters --region eu-north-1; \
echo "Remaining EC2 instances:"; \
aws ec2 describe-instances --region eu-north-1 \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}" \
  --output table; \
echo "Remaining Load Balancers:"; \
aws elbv2 describe-load-balancers --region eu-north-1 \
  --query "LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName}" \
  --output table