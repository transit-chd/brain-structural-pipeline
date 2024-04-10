# brain-structural-pipeline

_TRANSIT CHD project brain slice-to-volume reconstruction and tissue segmentation pipeline for T2-weighted fetal and neonatal MRI_

__run-brain-structural-pipeline-bash.sh__  
Script to run TRANSIT CHD structural brain pipeline: preprocessing, SVR, BOUNTI and reporting. 

Intended for use within automated SVRTK containe.  
Example:
```dockerfile
# Dockerfile 
# TRANSIT-CHD brain-structural-pipeline

FROM fetalsvrtk/svrtk:general_auto_amd

RUN git clone https://github.com/transit-chd/brain-structural-pipeline /home/scripts
```

__NOTE:__ Current implementation 
* for fetal data only; not yet implemented for neonatal
* requires directory with input T2-weighted stack files bound to /home/data/input, empty output directory bound to /home/data/output and a temp directory bound to /home/tmp_proc

Example using Singularity container image (transit-svrtk-auto.sif):
```shell
singularity exec --bind $INPUT_DIR:/home/data/input,$OUTPUT_DIR:/home/data/output,$TEMP_DIR:/home/tmp_proc transit-svrtk-auto.sif /bin/sh -c "/home/scripts/run-brain-structural-pipeline-bash.sh $STACK_SLICE_THICKNESS"
```
