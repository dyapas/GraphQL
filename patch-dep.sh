#!/bin/bash

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 <namespace>${NC}"
    exit 1
fi

NAMESPACE=$1
LOG_FILE="resource_patch_log.csv"
OLD_REG_HOST="quay.apps.ose4-prod.abc.com"
NEW_REG_HOST="quay.apps.ose4-dev.abc.com"

# Counters for summary
SUCCESS_COUNT=0
FAIL_COUNT=0

if [ ! -f "$LOG_FILE" ]; then
    echo "Namespace,ResourceType,ResourceName,ContainerType,ContainerName,Old_Image,New_Image,Status" > "$LOG_FILE"
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN} Scanning Namespace: $NAMESPACE${NC}"
echo -e "${CYAN} Resources: Deployments & StatefulSets${NC}"
echo -e "${CYAN}====================================================${NC}"

# Loop through both Deployments and StatefulSets
for KIND in deployment statefulset; do
    RESOURCES=$(oc get "$KIND" -n "$NAMESPACE" -o name 2>/dev/null)

    for RES in $RESOURCES; do
        RES_NAME=$(echo "$RES" | cut -d'/' -f2)

        # Loop through both standard containers and initContainers
        for C_TYPE in "containers" "initContainers"; do
            
            # Extract container data
            oc get "$RES" -n "$NAMESPACE" -o jsonpath="{range .spec.template.spec.$C_TYPE[*]}{.name}{\" \"}{.image}{\"\n\"}{end}" | while read -r C_NAME C_IMAGE; do
                
                if [[ "$C_IMAGE" == *"$OLD_REG_HOST"* ]]; then
                    NEW_IMAGE=$(echo "$C_IMAGE" | sed "s|$OLD_REG_HOST|$NEW_REG_HOST|")

                    echo -e "\n${YELLOW}[FOUND $KIND / $C_TYPE]${NC} $RES_NAME"
                    echo -e "  Container: $C_NAME"
                    echo -e "  Updating:  $C_IMAGE -> $NEW_IMAGE"

                    # Construct the strategic patch
                    PATCH_JSON="{\"spec\":{\"template\":{\"spec\":{\"$C_TYPE\":[{\"name\":\"$C_NAME\",\"image\":\"$NEW_IMAGE\"}]}}}}"
                    
                    if oc patch "$RES" -n "$NAMESPACE" --type='strategic' -p "$PATCH_JSON" > /dev/null 2>&1; then
                        echo -e "  ${GREEN}[SUCCESS]${NC} Applied patch."
                        echo "$NAMESPACE,$KIND,$RES_NAME,$C_TYPE,$C_NAME,$C_IMAGE,$NEW_IMAGE,SUCCESS" >> "$LOG_FILE"
                        ((SUCCESS_COUNT++))
                    else
                        echo -e "  ${RED}[FAILED]${NC} Check resource locks or permissions."
                        echo "$NAMESPACE,$KIND,$RES_NAME,$C_TYPE,$C_NAME,$C_IMAGE,$NEW_IMAGE,FAILED" >> "$LOG_FILE"
                        ((FAIL_COUNT++))
                    fi
                fi
            done
        done
    done
done

echo -e "\n${CYAN}====================================================${NC}"
echo -e " COMPLETED: $SUCCESS_COUNT Successes | $FAIL_COUNT Failures"
echo -e " Summary Log: ${GREEN}$LOG_FILE${NC}"
echo -e "${CYAN}====================================================${NC}"
