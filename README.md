# Initialising landscapes across Alaska and Canada

This workflow contains the code to reproduce iLand model runs in AK and CAN. This README is breif as the `description.qmd` contains the details.
Some scripts are translated from Winslow Hansen's originals and have been re-written to work with multiple landscapes.
The landscape selection scrip is bsaed on Lora Murphy's original. See the `description.qmd` for details.

The github repo _does not_ contain all the data necessary (e.g., the ABoVE landcover and surface water datasets) as these are large files.
These data are stored on Winslow's network drive and the pathways to network drive data are hard-coded in the scripts.
All links to download the relevant databases are recorded in script comments or the `description.qmd` to recreate the workflow.
The workflow _will_ download the nessary DEM and soil grid tiles based on landscape bounding boxes.

The code is not AI-generated; however, I used Claude Opus 4.7 and sonnet 4.6 as an assistant with much supervision for improvements and testing.

The `description.qmd` is written almost entirely by Claude, and describes each document in the workflow.
This was me experimenting with AI capabilities for documentation, and it did a pretty decent job!
I have revised the description to make sure it is correct, but it doesn't have my tone!

Bash scripts for running iLand are included in `data/shared-sml-create`.
