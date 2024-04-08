#!/usr/bin/env bash -l

#
# distributed under the terms of the 
# [GNU General Public License v3.0: 
# https://www.gnu.org/licenses/gpl-3.0.en.html. 
# 
# This program is free software: you can redistribute it and/or modify 
# it under the terms of the GNU General Public License as published by 
# the Free Software Foundation version 3 of the License. 
# 
# This software is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
# See the GNU General Public License for more details.
#

# Set bash strict mode (see:https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/)
set -Eeuo pipefail

# Usage
usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") TBD

Run basic TRANSIT CHD structural brain pipeline: preprocessing, SVR, BOUNTI and reporting 

Requires directory with input files bound to /home/data/input, output directory bound to /home/data/output and temp directory bound to /home/tmp_proc. 

Example container usage:
  singularity exec --bind \$INPUT_DIR:/home/data/input,\$OUTPUT_DIR:/home/data/output,\$TEMP_DIR:/home/tmp_proc svrtk-auto.sif /bin/sh -c "/home/scripts/run-brain-structural-pipeline-bash.sh \$STACK_SLICE_THICKNESS"

EOF
  exit
}

# Set Bind Paths
IN_DIR=/home/data/input
OUT_DIR=/home/data/output
TMP_DIR=/home/tmp_proc

# Validate Bind Paths
if [[ ! -d ${IN_DIR} ]];then
	echo "ERROR: NO FOLDER WITH THE INPUT FILES FOUND !!!!" 
  exit
else
  NUM_STACKS=$(find ${IN_DIR}/ -name "*.nii*" | wc -l)
  if [ $NUM_STACKS -eq 0 ];then
    echo "ERROR: NO INPUT .nii / .nii.gz FILES FOUND !!!!"
    exit
  fi
fi
if [[ ! -d ${OUT_DIR} ]];then
	echo "ERROR: NO OUTPUT FOLDER FOUND !!!!"
  exit
else
  if [ "$(ls -A $OUT_DIR)" ];then
  	echo "ERROR: OUTPUT FOLDER IS NOT EMPTY !!!!"
    ls -A $OUT_DIR
    exit
  fi
fi
if [[ ! -d ${TMP_DIR} ]];then
	echo "ERROR: NO TEMP FOLDER FOUND !!!!"
  exit
fi

# Parse Inputs
if [ $# -ne 1 ] ; then
  usage
else 
  STACK_SLICE_THICKNESS=$1  
fi

# Set Defaults
SVR_MOCO_MODE=0  # motion correction mode (see auto-brain-reconstruction.sh)
SVR_OUT_RES=0.8  # spatial resolution of reconstructed volume 
SVR_NUM_PKG=1    # number of packages (see auto-brain-reconstruction.sh)

# List Parameters
echo -e "\n\n=== TRANSIT CHD Brain Structural Pipeline (Basic) ==============================\n\n"
echo " - number of stacks : " $NUM_STACKS
echo " - input stack slice thickness : " $STACK_SLICE_THICKNESS

# Define Output Directories
STACK_DIR=$OUT_DIR/01_stacks
SVR_DIR=$OUT_DIR/02_svr
VOLUME_DIR=$OUT_DIR/03_volume
SEG_DIR=$OUT_DIR/04_bounti

# Bias Correction on Input T2w SSFSE Stacks
echo -e "\n\n=== 01 Bias Correction on T2w SSFSE Stacks =====================================\n\n"
mkdir $STACK_DIR
cd $IN_DIR
set -x
pwd
{ set +x; } 2>/dev/null
for FILE in *.nii*
do
  set -x
  mirtk N4 -i $FILE -o $STACK_DIR/$FILE -d 3 -c "[50x50x50,0.001]" -s 2 -b "[100,3]" -t "[0.15,0.01,200]" 
  { set +x; } 2>/dev/null
done

# Auto SVR
echo -e "\n\n=== 02 SVR =====================================================================\n\n"
mkdir $SVR_DIR
set -x
bash /home/auto-proc-svrtk/scripts/auto-brain-reconstruction.sh $STACK_DIR $SVR_DIR $SVR_MOCO_MODE $STACK_SLICE_THICKNESS $SVR_OUT_RES $SVR_NUM_PKG
{ set +x; } 2>/dev/null

# Bias Correction on Reconstructed T2w Volume
echo -e "\n\n=== 03 Bias Correction on T2w Volume ===========================================\n\n"
mkdir $VOLUME_DIR
set -x
mirtk threshold-image $SVR_DIR/reo-SVR-output-brain.nii.gz $VOLUME_DIR/mask.nii.gz 5
mirtk erode-image $VOLUME_DIR/mask.nii.gz $VOLUME_DIR/mask.nii.gz -iterations 2
mirtk extract-connected-components $VOLUME_DIR/mask.nii.gz $VOLUME_DIR/mask.nii.gz -n 1
mirtk dilate-image $VOLUME_DIR/mask.nii.gz $VOLUME_DIR/mask.nii.gz -iterations 2
mirtk close-image $VOLUME_DIR/mask.nii.gz $VOLUME_DIR/mask.nii.gz -iterations 4
mirtk N4 3 -i $SVR_DIR/reo-SVR-output-brain.nii.gz -x $VOLUME_DIR/mask.nii.gz -o "[$VOLUME_DIR/reo-SVR-output-brain-n4corr.nii.gz,$VOLUME_DIR/reo-SVR-output-brain-bias.nii.gz]" -c "[50x50x50,0.001]" -s 2 -b "[100,3]" -t "[0.15,0.01,200]" 
{ set +x; } 2>/dev/null

# Resample T2w Volume to Higher Resolution
echo -e "\n\n=== 03 Resample T2w Volume to Higher Resolution ================================\n\n"
set -x
mirtk resample-image $VOLUME_DIR/reo-SVR-output-brain-n4corr.nii.gz $VOLUME_DIR/reo-SVR-output-brain-n4corr-hires.nii.gz -isotropic 0.5 -interp Sinc
mirtk nan $VOLUME_DIR/reo-SVR-output-brain-n4corr-hires.nii.gz 1000000 # replace negative values with zero
{ set +x; } 2>/dev/null

# BOUNTI Segmentation
echo -e "\n\n=== 04 BOUNTI Segmentation =====================================================\n\n"
mkdir $SEG_DIR
cp $VOLUME_DIR/reo-SVR-output-brain-n4corr-hires.nii.gz $SEG_DIR
set -x
bash /home/auto-proc-svrtk/scripts/auto-brain-bounti-segmentation-fetal.sh $SEG_DIR $SEG_DIR
{ set +x; } 2>/dev/null

# Calculate Label Volumes
echo -e "\n\n=== 04 Calculate Label Volumes =================================================\n\n"
set -x
mirtk measure-volume $SEG_DIR/reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19.nii.gz > $SEG_DIR/measure-volume.txt
{ set +x; } 2>/dev/null

# Set File Permissions
chmod 0775 -R $OUT_DIR

# End
echo -e "\n\n=== TRANSIT CHD Brain Structural Pipeline (Basic) Complete =====================\n\n"
