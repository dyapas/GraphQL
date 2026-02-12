#!/bin/bash

# Check if namespace is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <namespace>"
    exit 1
fi

NAMESPACE=$1
LOG_FILE="image_patch_log.csv"
OLD_REGISTRY="quay.apps.ose4-prod.abc.com"
NEW_REGISTRY="quay.apps.ose4-dev.abc.com"

# Initialize log file with header if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    echo "Namespace,Deployment,Container,Old_Image,New_Image" > "$LOG_FILE"
fi

echo "Starting patch process in namespace: $NAMESPACE..."

# Get all deployments in the namespace
DEPLOYMENTS=$(oc get deployments -n "$NAMESPACE" -o name)

for DEP in $DEPLOYMENTS; do
    # Get deployment name without the 'deployment.apps/' prefix
    DEP_NAME=$(echo "$DEP" | cut -d'/' -f2)

    # Get container details: name and image
    # Output format: containerName imagePath
    oc get deployment "$DEP_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{.image}{"\n"}{end}' | while read -r C_NAME C_IMAGE; do
        
        # Check if the container image contains the old registry string
        if [[ "$C_IMAGE" == *"$OLD_REGISTRY"* ]]; then
            NEW_IMAGE=$(echo "$C_IMAGE" | sed "s|$OLD_REGISTRY|$NEW_REGISTRY|")

            echo "Patching $DEP_NAME container $C_NAME..."

            # Apply the patch to the specific container
            # We use a strategic merge patch to update the image field
            oc patch deployment "$DEP_NAME" -n "$NAMESPACE" --type='strategy' -p \
                "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$C_NAME\",\"image\":\"$NEW_IMAGE\"}]}}}}" > /dev/null

            # Log the change
            echo "$NAMESPACE,$DEP_NAME,$C_NAME,$C_IMAGE,$NEW_IMAGE" >> "$LOG_FILE"
        fi
    done
done

echo "Process complete. Details logged to $LOG_FILE."
