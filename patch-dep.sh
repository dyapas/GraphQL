#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if namespace is provided
if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 <namespace>${NC}"
    exit 1
fi

NAMESPACE=$1
LOG_FILE="image_patch_log.csv"
OLD_REGISTRY="quay.apps.ose4-prod.abc.com"
NEW_REGISTRY="quay.apps.ose4-dev.abc.com"

# Initialize log file with header if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    echo "Namespace,Deployment,Container,Old_Image,New_Image,Status" > "$LOG_FILE"
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN} Starting Update in Namespace: $NAMESPACE${NC}"
echo -e "${CYAN}====================================================${NC}"

# Get all deployments in the namespace
DEPLOYMENTS=$(oc get deployments -n "$NAMESPACE" -o name)

for DEP in $DEPLOYMENTS; do
    DEP_NAME=$(echo "$DEP" | cut -d'/' -f2)

    # Extract container name and image pairs
    oc get deployment "$DEP_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{.image}{"\n"}{end}' | while read -r C_NAME C_IMAGE; do
        
        if [[ "$C_IMAGE" == *"$OLD_REGISTRY"* ]]; then
            NEW_IMAGE=$(echo "$C_IMAGE" | sed "s|$OLD_REGISTRY|$NEW_REGISTRY|")

            # Display the update details to the terminal
            echo -e "\n${CYAN}Deployment:${NC} $DEP_NAME"
            echo -e "${CYAN}Container: ${NC} $C_NAME"
            echo -e "${RED}Current:   ${NC} $C_IMAGE"
            echo -e "${GREEN}New:       ${NC} $NEW_IMAGE"

            # Prepare the strategic patch
            PATCH_JSON="{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$C_NAME\",\"image\":\"$NEW_IMAGE\"}]}}}}"
            
            # Execute patch and check status
            if oc patch deployment "$DEP_NAME" -n "$NAMESPACE" --type='strategic' -p "$PATCH_JSON" > /dev/null 2>&1; then
                echo -e "${GREEN}[SUCCESS]${NC} Resource updated in OpenShift."
                echo "$NAMESPACE,$DEP_NAME,$C_NAME,$C_IMAGE,$NEW_IMAGE,SUCCESS" >> "$LOG_FILE"
            else
                echo -e "${RED}[FAILED]${NC} Could not update resource."
                echo "$NAMESPACE,$DEP_NAME,$C_NAME,$C_IMAGE,$NEW_IMAGE,FAILED" >> "$LOG_FILE"
            fi
        fi
    done
done

echo -e "\n${CYAN}====================================================${NC}"
echo -e "Finished! CSV log saved to: ${GREEN}$LOG_FILE${NC}"
