```
export KUBECONFIG=/home/hedlund01/.kube/config && /usr/bin/minikube kubectl -- annotate gitrepository flux-local -n flux-local reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```
Forces flux to reconcile new pushes.