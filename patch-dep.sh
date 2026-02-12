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
# Dynamic log file name based on namespace
LOG_FILE="patch_log_${NAMESPACE}.csv"
OLD_REG_HOST="quay.apps.ose4-prod.abc.com"
NEW_REG_HOST="quay.apps.ose4-dev.abc.com"

SUCCESS_COUNT=0
FAIL_COUNT=0

# Initialize the namespace-specific log file
if [ ! -f "$LOG_FILE" ]; then
    echo "Namespace,ResourceType,ResourceName,OriginalReplicas,ContainerType,ContainerName,OldImage,NewImage,Status" > "$LOG_FILE"
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN} Target Namespace: $NAMESPACE${NC}"
echo -e "${CYAN} Log File:        $LOG_FILE${NC}"
echo -e "${CYAN}====================================================${NC}"

# Check if namespace exists/accessible
if ! oc get project "$NAMESPACE" > /dev/null 2>&1; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' not found or no access.${NC}"
    exit 1
fi

for KIND in deployment statefulset; do
    RESOURCES=$(oc get "$KIND" -n "$NAMESPACE" -o name 2>/dev/null)

    for RES in $RESOURCES; do
        RES_NAME=$(echo "$RES" | cut -d'/' -f2)
        
        # Check if the resource actually contains the old registry before doing anything
        NEEDS_PATCH=$(oc get "$RES" -n "$NAMESPACE" -o jsonpath='{..image}' | grep "$OLD_REG_HOST")

        if [ ! -z "$NEEDS_PATCH" ]; then
            # 1. Capture current replica count
            REPLICAS=$(oc get "$RES" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            [ -z "$REPLICAS" ] && REPLICAS=0

            echo -e "\n${YELLOW}[PROCESSING]${NC} $RES_NAME (Current Replicas: $REPLICAS)"
            
            # 2. Scale down to 0
            echo -e "  Scaling down to 0..."
            oc scale "$RES" -n "$NAMESPACE" --replicas=0 > /dev/null 2>&1

            # 3. Iterate through both standard and init containers
            for C_TYPE in "containers" "initContainers"; do
                oc get "$RES" -n "$NAMESPACE" -o jsonpath="{range .spec.template.spec.$C_TYPE[*]}{.name}{\" \"}{.image}{\"\n\"}{end}" | while read -r C_NAME C_IMAGE; do
                    
                    if [[ "$C_IMAGE" == *"$OLD_REG_HOST"* ]]; then
                        NEW_IMAGE=$(echo "$C_IMAGE" | sed "s|$OLD_REG_HOST|$NEW_REG_HOST|")
                        
                        echo -e "  Updating $C_TYPE: $C_NAME"
                        echo -e "  From: $C_IMAGE"
                        echo -e "  To:   $NEW_IMAGE"

                        # Apply strategic patch
                        PATCH_JSON="{\"spec\":{\"template\":{\"spec\":{\"$C_TYPE\":[{\"name\":\"$C_NAME\",\"image\":\"$NEW_IMAGE\"}]}}}}"
                        
                        if oc patch "$RES" -n "$NAMESPACE" --type='strategic' -p "$PATCH_JSON" > /dev/null 2>&1; then
                            echo -e "  ${GREEN}[SUCCESS]${NC} Image patched."
                            echo "$NAMESPACE,$KIND,$RES_NAME,$REPLICAS,$C_TYPE,$C_NAME,$C_IMAGE,$NEW_IMAGE,SUCCESS" >> "$LOG_FILE"
                            ((SUCCESS_COUNT++))
                        else
                            echo -e "  ${RED}[FAILED]${NC} Patching failed."
                            echo "$NAMESPACE,$KIND,$RES_NAME,$REPLICAS,$C_TYPE,$C_NAME,$C_IMAGE,$NEW_IMAGE,FAILED" >> "$LOG_FILE"
                            ((FAIL_COUNT++))
                        fi
                    fi
                done
            done

            # 4. Scale back up to the original count
            echo -e "  Restoring to $REPLICAS replicas..."
            oc scale "$RES" -n "$NAMESPACE" --replicas="$REPLICAS" > /dev/null 2>&1
        fi
    done
done

echo -e "\n${CYAN}====================================================${NC}"
echo -e " COMPLETED: $SUCCESS_COUNT success, $FAIL_COUNT failure"
echo -e " Logs saved to: ${GREEN}$LOG_FILE${NC}"
echo -e "${CYAN}====================================================${NC}"
