#!/bin/sh
set -eu

NAMESPACE="${K8S_NAMESPACE:-aceest}"
STRATEGY="${1:-rolling}"
IMAGE="${IMAGE:?Set IMAGE to a versioned container image}"

apply_image_manifest() {
    sed "s|IMAGE_PLACEHOLDER|$2|g" "$1" | \
        kubectl apply --namespace "$NAMESPACE" -f -
}

prepare_common_resources() {
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/storage.yaml
}

ensure_stable_deployment() {
    if ! kubectl get deployment aceest-fitness \
        --namespace "$NAMESPACE" >/dev/null 2>&1; then
        apply_image_manifest k8s/deployment.yaml "$IMAGE"
        kubectl rollout status deployment/aceest-fitness \
            --namespace "$NAMESPACE" --timeout=180s
    fi
}

wait_for_deployment() {
    kubectl rollout status "deployment/$1" \
        --namespace "$NAMESPACE" --timeout=180s
}

smoke_test_service() {
    SERVICE="$1"
    LOG_FILE=$(mktemp)
    kubectl port-forward --namespace "$NAMESPACE" \
        "service/$SERVICE" 18080:80 >"$LOG_FILE" 2>&1 &
    PORT_FORWARD_PID=$!
    trap 'kill "$PORT_FORWARD_PID" 2>/dev/null || true; rm -f "$LOG_FILE"' EXIT

    for attempt in $(seq 1 30); do
        if curl --fail --silent http://127.0.0.1:18080/readyz; then
            return 0
        fi
        sleep 2
    done
    cat "$LOG_FILE" >&2
    return 1
}

remove_alternative_ingresses() {
    kubectl apply -f k8s/namespace.yaml
    for ingress in aceest-canary aceest-ab-test aceest-shadow-mirror; do
        kubectl delete ingress "$ingress" --namespace "$NAMESPACE" \
            --ignore-not-found
    done
}

deploy_rolling() {
    remove_alternative_ingresses
    prepare_common_resources
    apply_image_manifest k8s/deployment.yaml "$IMAGE"
    if ! wait_for_deployment aceest-fitness; then
        kubectl rollout undo deployment/aceest-fitness \
            --namespace "$NAMESPACE" || true
        return 1
    fi
    kubectl apply -f k8s/service.yaml
    kubectl apply -f k8s/ingress/stable.yaml
    if ! smoke_test_service aceest-fitness; then
        kubectl rollout undo deployment/aceest-fitness \
            --namespace "$NAMESPACE" || true
        return 1
    fi
}

deploy_blue_green() {
    remove_alternative_ingresses
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/storage.yaml
    if ! kubectl get service aceest-fitness \
        --namespace "$NAMESPACE" >/dev/null 2>&1 ||
        [ -z "$(kubectl get service aceest-fitness --namespace "$NAMESPACE" \
            -o jsonpath='{.spec.selector.slot}')" ]; then
        if kubectl get deployment aceest-fitness \
            --namespace "$NAMESPACE" >/dev/null 2>&1; then
            ACTIVE_IMAGE=$(kubectl get deployment aceest-fitness \
                --namespace "$NAMESPACE" \
                -o jsonpath='{.spec.template.spec.containers[0].image}')
        else
            ACTIVE_IMAGE="$IMAGE"
        fi
        apply_image_manifest k8s/strategies/blue-green.yaml "$ACTIVE_IMAGE"
    fi
    kubectl apply -f k8s/ingress/stable.yaml

    ACTIVE_SLOT=$(kubectl get service aceest-fitness \
        --namespace "$NAMESPACE" \
        -o jsonpath='{.spec.selector.slot}')
    case "$ACTIVE_SLOT" in
        blue) CANDIDATE_SLOT=green ;;
        green) CANDIDATE_SLOT=blue ;;
        *)
            echo "Service selector has no recognized blue/green slot." >&2
            return 1
            ;;
    esac

    if ! kubectl get deployment "aceest-$CANDIDATE_SLOT" \
        --namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo "Candidate deployment aceest-$CANDIDATE_SLOT is missing." >&2
        return 1
    fi
    kubectl set image "deployment/aceest-$CANDIDATE_SLOT" \
        "app=$IMAGE" --namespace "$NAMESPACE"
    if ! wait_for_deployment "aceest-$CANDIDATE_SLOT"; then
        return 1
    fi
    sh k8s/promote-blue-green.sh "$CANDIDATE_SLOT"
    if ! smoke_test_service aceest-fitness; then
        sh k8s/rollback.sh blue-green
        return 1
    fi
}

deploy_canary() {
    remove_alternative_ingresses
    prepare_common_resources
    ensure_stable_deployment
    kubectl apply -f k8s/service.yaml
    apply_image_manifest k8s/strategies/canary.yaml "$IMAGE"
    kubectl apply -f k8s/ingress/stable.yaml
    kubectl delete ingress aceest-ab-test --namespace "$NAMESPACE" \
        --ignore-not-found
    kubectl apply -f k8s/strategies/canary-ingress.yaml
    if ! wait_for_deployment aceest-canary ||
        ! smoke_test_service aceest-canary; then
        sh k8s/rollback.sh canary
        return 1
    fi
}

deploy_ab() {
    remove_alternative_ingresses
    prepare_common_resources
    ensure_stable_deployment
    kubectl apply -f k8s/service.yaml
    apply_image_manifest k8s/strategies/canary.yaml "$IMAGE"
    kubectl apply -f k8s/ingress/stable.yaml
    kubectl delete ingress aceest-canary --namespace "$NAMESPACE" \
        --ignore-not-found
    kubectl apply -f k8s/strategies/ab-test.yaml
    if ! wait_for_deployment aceest-canary ||
        ! smoke_test_service aceest-canary; then
        sh k8s/rollback.sh ab
        return 1
    fi
}

deploy_shadow() {
    remove_alternative_ingresses
    prepare_common_resources
    ensure_stable_deployment
    kubectl apply -f k8s/service.yaml
    apply_image_manifest k8s/strategies/shadow.yaml "$IMAGE"
    kubectl delete ingress aceest-stable --namespace "$NAMESPACE" \
        --ignore-not-found
    kubectl apply -f k8s/strategies/shadow-ingress.yaml
    if ! wait_for_deployment aceest-shadow ||
        ! smoke_test_service aceest-fitness; then
        sh k8s/rollback.sh shadow
        return 1
    fi
}

case "$STRATEGY" in
    rolling) deploy_rolling ;;
    blue-green) deploy_blue_green ;;
    canary) deploy_canary ;;
    ab) deploy_ab ;;
    shadow) deploy_shadow ;;
    *)
        echo "Usage: $0 {rolling|blue-green|canary|ab|shadow}" >&2
        exit 2
        ;;
esac
