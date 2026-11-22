#!/bin/sh
set -eu

NAMESPACE="${K8S_NAMESPACE:-aceest}"
STRATEGY="${1:-rolling}"

case "$STRATEGY" in
    rolling)
        kubectl rollout undo deployment/aceest-fitness --namespace "$NAMESPACE"
        ;;
    blue-green)
        ACTIVE_SLOT=$(kubectl get service aceest-fitness \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.spec.selector.slot}')
        ROLLBACK_SLOT=$(kubectl get service aceest-fitness \
            --namespace "$NAMESPACE" \
            -o 'jsonpath={.metadata.annotations.aceest\.io/previous-slot}')
        if [ "$ACTIVE_SLOT" = "$ROLLBACK_SLOT" ] || \
            { [ "$ROLLBACK_SLOT" != blue ] && [ "$ROLLBACK_SLOT" != green ]; }; then
            echo "No previous blue/green slot is recorded on the service." >&2
            exit 1
        fi
        kubectl patch service aceest-fitness \
            --namespace "$NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"selector\":{\"app\":\"aceest-fitness\",\"slot\":\"$ROLLBACK_SLOT\"}}}"
        kubectl annotate service aceest-fitness \
            --namespace "$NAMESPACE" \
            "aceest.io/previous-slot=$ACTIVE_SLOT" \
            --overwrite
        ;;
    canary)
        kubectl annotate ingress aceest-canary \
            --namespace "$NAMESPACE" \
            nginx.ingress.kubernetes.io/canary-weight="0" \
            --overwrite
        ;;
    ab)
        kubectl delete ingress aceest-ab-test \
            --namespace "$NAMESPACE" \
            --ignore-not-found
        ;;
    shadow)
        kubectl delete ingress aceest-shadow-mirror \
            --namespace "$NAMESPACE" \
            --ignore-not-found
        kubectl apply -f k8s/ingress/stable.yaml
        ;;
    *)
        echo "Usage: $0 {rolling|blue-green|canary|ab|shadow}" >&2
        exit 2
        ;;
esac
