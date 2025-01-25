#!/bin/bash

NEXUS_URL="https://index.docker.io/v1/"
# NEXUS_URL="datafabrik-docker-hosted-repo.anah.fr"

# Default values for search paths and images
SEARCH_PATHS=(
"/home/mboutray/code/vectorive/test-nexus-tag/jupyter"
"/home/mboutray/code/vectorive/test-nexus-tag/superset"
# "$HOME/project3"
)
HARDCODED_IMAGES=(
"redis:7"
)

# Function to check if an image is already tagged with the Nexus URL
is_nexus_image() {
    local image=$1
    if [[ $image == $NEXUS_URL* ]]; then
        return 1
    else
        return 0 
    fi
}

# Function to verify if the user is logged in to the Nexus repository
is_logged_into_nexus() {
    if [[ -f "$HOME/.docker/config.json" ]]; then
        auth_entry=$(jq -r --arg url "$NEXUS_URL" '.auths[$url] // empty' < "$HOME/.docker/config.json")
        if [[ -n "$auth_entry" ]]; then
            echo -e "Logged in to the Nexus repository at $NEXUS_URL.\n"
            return 0 # Logged in
        fi
    fi
    echo -e "Error: Not logged in to the Nexus repository at $NEXUS_URL. Please run 'docker login $NEXUS_URL' first.\n"
    exit 1
}

# Function to extract images from a docker-compose.yml file
extract_images_from_compose() {
    local compose_file=$1

    # Extract image from the "image:" key
    docker compose -f "$compose_file" config | grep "image:" | awk '{print $2}'

    # Extract images under the "tags:" key in the "build:" section, if present
    docker compose -f "$compose_file" config | awk '
    /tags:/ {flag=1; next}   # Start capturing after "tags:" line
    /^[^[:space:]]/ {flag=0} # Stop capturing when indentation decreases
    flag && /- / {print $2}  # Print only lines with "- " (tags)
    '
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

  If no arguments are provided, the script uses predefined default search paths and hardcoded images.
EOF
    exit 0
}

# Handle user input and arguments
handle_arguments() {
    if [[ $# -eq 0 ]]; then
        # If no arguments are provided, use default values
        return
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                display_help
                ;;
            -s|--search-path)
                if [[ -n "$2" ]]; then
                    SEARCH_PATHS+=("$2")
                    shift
                else
                    echo "Error: --search-path requires a value."
                    exit 1
                fi
                ;;
            -i|--image)
                if [[ -n "$2" ]]; then
                    HARDCODED_IMAGES+=("$2")
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
}

# Process script arguments
handle_arguments "$@"

# Verify login to Nexus repository
is_logged_into_nexus

# Search for docker-compose.yml files in specified paths and extract images and tags
IMAGES=()
for search_path in "${SEARCH_PATHS[@]}"; do
    for compose_file in $(find "$search_path" -name "docker-compose.yml" -o -name "docker-compose.yaml"); do
        echo "Scanning $compose_file for images..."
        while IFS= read -r image; do
            if [[ -n "$image" ]]; then # Only add non-empty image entries
                echo "Found image $image in $compose_file"
                IMAGES+=("$image")
            fi
        done < <(extract_images_from_compose "$compose_file")
    done
    echo
done

# # Add hardcoded images to the list
for image in "${HARDCODED_IMAGES[@]}"; do
    echo "Adding hardcoded image $image to the list"
    IMAGES+=("$image")
done

# # Tag and push each image
# for IMAGE in "${IMAGES[@]}"; do
#     if is_nexus_image "$IMAGE"; then
#         # If the image is already tagged with the Nexus URL, push it directly
#         echo "Image $IMAGE is already tagged with the Nexus URL."
#         echo "Pushing $IMAGE"
#         docker push "$IMAGE"
#     else
#         # If the image is not tagged with the Nexus URL, tag it
#         IMAGE_NAME=$(echo "$IMAGE" | cut -d":" -f1)
#         IMAGE_TAG=$(echo "$IMAGE" | cut -d":" -f2)

#         TAGGED_IMAGE="$NEXUS_URL/$IMAGE_NAME:$IMAGE_TAG"
#         echo "Tagging $IMAGE as $TAGGED_IMAGE"
#         docker tag "$IMAGE" "$TAGGED_IMAGE"

#         echo "Pushing $TAGGED_IMAGE"
#         docker push "$TAGGED_IMAGE"
#     fi
# done
