#!/bin/bash

NEXUS_URL="datafabrik-docker-hosted-repo.anah.fr"
DEFAULT_SEARCH_PATHS=(
    "$HOME/jupyter"
    "$HOME/openmetadata"
    "$HOME/pgadmin"
    "$HOME/superset"
    "$HOME/traefik"
)
DEFAULT_IMAGES=(
    "portainer/agent:2.19.4"
)

# Override the default constants
source $(dirname $0)/overrides.sh

# Declare an associative array to store unique images
declare -A IMAGES
SEARCH_PATHS=()

# Function to check if an image is already tagged with the Nexus URL
is_nexus_image() {
    local image=$1
    [[ $image == $NEXUS_URL* ]]
}

# Function to verify if the user is logged in to the Nexus repository
is_logged_into_nexus() {
    if [[ -f "$HOME/.docker/config.json" ]]; then
        auth_entry=$(jq -r --arg url "$NEXUS_URL" '.auths[$url] // empty' < "$HOME/.docker/config.json")
        if [[ -n "$auth_entry" ]]; then
            echo -e "Logged in to the Nexus repository at $NEXUS_URL.\n"
            return 0
        fi
    fi
    echo -e "Error: Not logged in to the Nexus repository at $NEXUS_URL. Please run 'docker login $NEXUS_URL' first.\n"
    exit 1
}

# Function to extract images from a docker-compose.yml file
extract_images_from_compose() {
    local compose_file=$1
    local profiles=($(docker compose -f "$compose_file" config --profiles 2>/dev/null))
    local profile_args=()

    for profile in "${profiles[@]}"; do
        profile_args+=("--profile=$profile")
    done

    # Extract images from "image:" key (allow both namespaced and non-namespaced images)
    docker compose -f "$compose_file" "${profile_args[@]}" config | \
        awk '/image:/ {print $2}' | grep -E '^([a-zA-Z0-9_.-]+/)?[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.-]+$'

    # Extract images under "tags:" key in "build:" section
    docker compose -f "$compose_file" "${profile_args[@]}" config | awk '
    /tags:/ {flag=1; next} 
    /^[^[:space:]]/ {flag=0} 
    flag && /- / {print $2}' | grep -E '^([a-zA-Z0-9_.-]+/)?[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.-]+$'
}

# Display help message
display_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help               Show this help message and exit.
  -s, --search-path PATH   Specify a search path. Can be used multiple times.
  -i, --image IMAGE        Specify an image to push. Can be used multiple times.

Description:
  This script scans docker-compose.yml and docker-compose.yaml files in the specified or default paths,
  extracts Docker image names, and pushes them to the Nexus repository. Additionally, specific
  images can be included manually.

  If no arguments are provided, the script uses predefined default search paths and images.
EOF
    exit 0
}

# Handle user input and arguments
handle_arguments() {
    local has_custom_input=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                display_help
                ;;
            -s|--search-path)
                if [[ -n "$2" ]]; then
                    SEARCH_PATHS+=("$2")
                    has_custom_input=true
                    shift
                else
                    echo "Error: --search-path requires a value."
                    exit 1
                fi
                ;;
            -i|--image)
                if [[ -n "$2" ]]; then
                    IMAGES["$2"]=1
                    has_custom_input=true
                    shift
                else
                    echo "Error: --image requires a value."
                    exit 1
                fi
                ;;
            *)
                echo "Error: Unknown option $1"
                display_help
                ;;
        esac
        shift
    done

    if [[ "$has_custom_input" == false ]]; then
        SEARCH_PATHS=("${DEFAULT_SEARCH_PATHS[@]}")
        for image in "${DEFAULT_IMAGES[@]}"; do
            IMAGES["$image"]=1
        done
    fi
}

handle_arguments "$@"

is_logged_into_nexus

current_step=1

if [[ ${#SEARCH_PATHS[@]} -gt 0 ]]; then
    echo -e "---------- Step $current_step: Finding images in projects ----------\n"

    # Search for docker-compose.yml files in specified paths and extract images
    for search_path in "${SEARCH_PATHS[@]}"; do
        for compose_file in $(find "$search_path" -name "docker-compose.yml" -o -name "docker-compose.yaml"); do
            echo "Scanning $compose_file for images."
            while IFS= read -r image; do
                if [[ -n "$image" ]]; then
                    echo "Found $image"
                    IMAGES["$image"]=1
                fi
            done < <(extract_images_from_compose "$compose_file")
        done
        echo
    done

    current_step=$((current_step+1))
fi

if [[ ${#IMAGES[@]} -gt 0 ]]; then
    echo -e "---------- Step $current_step: Tagging and pushing images ----------\n"

    # Tag and push each image
    for IMAGE in "${!IMAGES[@]}"; do
        if is_nexus_image "$IMAGE"; then
            echo "Image $IMAGE is already tagged with the Nexus URL."
            echo "Pushing $IMAGE"
            docker push "$IMAGE"
        else
            IMAGE_NAME=$(echo "$IMAGE" | cut -d":" -f1)
            IMAGE_TAG=$(echo "$IMAGE" | cut -d":" -f2)

            TAGGED_IMAGE="$NEXUS_URL/$IMAGE_NAME:$IMAGE_TAG"
            echo "Tagging $IMAGE as $TAGGED_IMAGE"
            docker tag "$IMAGE" "$TAGGED_IMAGE"

            echo "Pushing $TAGGED_IMAGE"
            docker push "$TAGGED_IMAGE"
        fi
        echo
    done
fi
