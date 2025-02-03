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
