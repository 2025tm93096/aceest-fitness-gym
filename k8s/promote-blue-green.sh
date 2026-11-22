#!/bin/sh
set -eu

NAMESPACE="${K8S_NAMESPACE:-aceest}"
CANDIDATE_SLOT="${1:-}"

case "$CANDIDATE_SLOT" in
    blue|green) ;;
    *)
        echo "Usage: $0 {blue|green}" >&2
        exit 2
        ;;
esac

ACTIVE_SLOT=$(kubectl get service aceest-fitness \
    --namespace "$NAMESPACE" \
    -o jsonpath='{.spec.selector.slot}')
if [ "$ACTIVE_SLOT" = "$CANDIDATE_SLOT" ]; then
    echo "Candidate slot $CANDIDATE_SLOT is already serving traffic." >&2
    exit 1
fi

kubectl rollout status "deployment/aceest-$CANDIDATE_SLOT" \
    --namespace "$NAMESPACE" \
    --timeout=180s
kubectl annotate service aceest-fitness \
    --namespace "$NAMESPACE" \
    "aceest.io/previous-slot=$ACTIVE_SLOT" \
    --overwrite
kubectl patch service aceest-fitness \
    --namespace "$NAMESPACE" \
    --type merge \
    -p "{\"spec\":{\"selector\":{\"app\":\"aceest-fitness\",\"slot\":\"$CANDIDATE_SLOT\"}}}"
