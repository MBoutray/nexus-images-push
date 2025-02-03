# Nexus

This project was done to update the push-images script used by Vectorive to push their images to their Nexus registry.  
I tried to make it more robust and extend its functionnality.

## Script

This scripts scans the projects for docker images. It tags the ones it finds and pushes them to Nexus.  
You can get help for this script by using the `--help` argument with it.

One can override the NEXUS_URL, DEFAULT_SEARCH_PATHS, and DEFAULT_IMAGES constants by including an  
`overrides.sh` file in the directory with their new definitions.
