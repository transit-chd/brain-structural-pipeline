#!/usr/bin/env bash

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
Usage: $(basename "${BASH_SOURCE[0]}") [-h] --stackslicethickness thickness_value

Run basic TRANSIT CHD structural brain pipeline: preprocessing, SVR, BOUNTI and reporting 

Available options:

-h, --help            Print this help and exit
--stackslicethickness Slice thickness of input stacks in millimeters

Requires directory with input files bound to /home/data/input, output directory bound to /home/data/output and temp directory bound to /home/tmp_proc. 

Example container usage:
  singularity exec --bind \$INPUT_DIR:/home/data/input,\$OUTPUT_DIR:/home/data/output,\$TEMP_DIR:/home/tmp_proc svrtk-auto.sif /bin/sh -c "/home/scripts/run-brain-structural-pipeline.sh --stackslicethickness \$STACK_SLICE_THICKNESS"

EOF
  exit
}

# Set Defaults
SVR_MOCO_MODE=0  # motion correction mode (see auto-brain-reconstruction.sh)
SVR_OUT_RES=0.8  # spatial resolution of reconstructed volume 
SVR_NUM_PKG=1    # number of packages (see auto-brain-reconstruction.sh)

# Parse Inputs
if [ $# -eq 0 ] ; then
  usage
fi
while :; do
  case "${1-}" in
  -h | --help) usage ;;
  --stackslicethickness) 
    STACK_SLICE_THICKNESS="${2-}"  # slice thickness of input stacks (in mm)
    shift
    ;;
  -?*) echo "Unknown option: $1" && exit;;
  *) break ;;
  esac
  shift
done
[[ -z "${STACK_SLICE_THICKNESS-}" ]] && echo "--stackslicethickness not specified" && exit; # check required parameter

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
input_volumes="$SEG_DIR/measure-volume.txt"
output_volumes="calc-volumes.txt"
# Read the file and extract integers into an indexed array
declare -a orderedVals=(0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)
mapfile -t inLabels < <(awk '{print $1}' "$input_volumes")
mapfile -t inVals < <(awk '{print $2}' "$input_volumes")
# Order values in array
for i in $(seq 0 18);
do
    X=${inLabels[$i]}-1
    orderedVals[$X]=${inVals[$i]}
done
# Values
# Cortical grey matter
cGML=${orderedVals[2]}
cGMR=${orderedVals[3]}
# White matter
WML=${orderedVals[4]}
WMR=${orderedVals[5]}
# Deep gray matter
THALL=${orderedVals[15]}
THALR=${orderedVals[16]}
GANGL=${orderedVals[13]}
GANGR=${orderedVals[14]}
# Cerebellum
CERL=${orderedVals[10]}
CERR=${orderedVals[11]}
CERV=${orderedVals[12]}
# Cerebrospinal fluid
ECSFL=${orderedVals[0]}
ECSFR=${orderedVals[1]}
LVENTL=${orderedVals[6]}
LVENTR=${orderedVals[7]}
CAV=${orderedVals[8]}
TVENT=${orderedVals[17]}
FVENT=${orderedVals[18]}
# Total brain volume
STEM=${orderedVals[9]}
# Calculate volumes
cGM=$(echo "$cGML + $cGMR" | bc)
WM=$(echo "$WML + $WMR" | bc)
dGM=$(echo "$THALL + $THALR + $GANGL + $GANGR" | bc)
CER=$(echo "$CERL + $CERR + $CERV" | bc)
CSF=$(echo "$ECSFL + $ECSFR + $LVENTL + $LVENTR + $CAV + $TVENT + $FVENT" | bc)
TBV=$(echo "$cGM + $WM + $dGM + $CER + $STEM" | bc)
# Print to calc-volumes.txt
{
    echo "cGM $cGM"
    echo "WM $WM"
    echo "dGM $dGM"
    echo "CER $CER"
    echo "CSF $CSF"
    echo "TBV $TBV"
} > "$SEG_DIR/$output_volumes"

{ set +x; } 2>/dev/null

# Create Slicer Scene File
echo -e "\n\n=== 04 Creating Slicer Scene File ==============================================\n\n"
# BOUNTI-19 Labels
echo -e "BOUNTI labels: $SEG_DIR/bounti-19.txt"
cat > $SEG_DIR/bounti-19.txt << EOF
# BOUNTI-19 Labels
1 eCSF_L 235 77 98 255
2 eCSF_R 255 183 0 255
3 Cortical_GM_L 0 0 255 255
4 Cortical_GM_R 177 0 253 255
5 Fetal_WM_L 0 255 255 255
6 Fetal_WM_R 182 255 79 255
7 Lateral_Ventricle_L 74 140 0 255
8 Lateral_Ventricle_R 0 51 205 255
9 Cavum_Septum_Pellucidum 244 93 222 255
10 Brainstem 0 74 140 255
11 Cerebellum_L 102 205 104 255
12 Cerebellum_R 104 104 239 255
13 Cerebellar_Vermis 117 0 60 255
14 Basal_Ganglia_L 235 0 161 255
15 Basal_Ganglia_R 255 8 0 255
16 Thalamus_L 96 36 144 255
17 Thalamus_R 153 120 0 255
18 Third_Ventricle 132 65 255 255
19 Fourth_Ventricle 183 144 139 255
EOF
# Slicer Scene
echo -e "Slicer scene: $SEG_DIR/bounti-19.txt"
cat > $SEG_DIR/segmentation-scene.mrml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<MRML version="Slicer" userTags="">
 <Slice
  id="vtkMRMLSliceNodeRed" name="Red" hideFromEditors="false" selectable="true" selected="false" singletonTag="Red" attributes="MappedInLayout:1" layoutLabel="R" layoutName="Red" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.952941 0.290196 0.2" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="195.618 137.6 0.4" dimensions="381 268 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="195.618 137.6 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="-1 0 0 1.2 0 1 0 1.6 0 0 1 5.8 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Axial" defaultOrientation="Axial" orientationReference="Axial" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <Slice
  id="vtkMRMLSliceNodeGreen" name="Green" hideFromEditors="false" selectable="true" selected="false" singletonTag="Green" attributes="MappedInLayout:1" layoutLabel="G" layoutName="Green" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.431373 0.690196 0.294118" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="183.793 128.8 0.4" dimensions="381 267 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="183.793 128.8 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="-1 0 0 1.2 0 0 1 -7.4 0 1 0 1.6 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Coronal" defaultOrientation="Coronal" orientationReference="Coronal" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <Slice
  id="vtkMRMLSliceNodeYellow" name="Yellow" hideFromEditors="false" selectable="true" selected="false" singletonTag="Yellow" attributes="MappedInLayout:1" layoutLabel="Y" layoutName="Yellow" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.929412 0.835294 0.298039" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="183.311 128.8 0.4" dimensions="380 267 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="183.311 128.8 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="0 0 -1 -7.4 -1 0 0 1.6 0 1 0 1.6 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Sagittal" defaultOrientation="Sagittal" orientationReference="Sagittal" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeRed" name="SliceComposite" hideFromEditors="true" selectable="true" selected="false" singletonTag="Red" references="backgroundVolume:vtkMRMLScalarVolumeNode1;labelVolume:vtkMRMLLabelMapVolumeNode1;" compositing="0" foregroundOpacity="0" labelOpacity="0.5" linkedControl="1" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Red" doPropagateVolumeSelection="1" ></SliceComposite>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeGreen" name="SliceComposite_1" hideFromEditors="true" selectable="true" selected="false" singletonTag="Green" references="backgroundVolume:vtkMRMLScalarVolumeNode1;labelVolume:vtkMRMLLabelMapVolumeNode1;" compositing="0" foregroundOpacity="0" labelOpacity="0.5" linkedControl="1" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Green" doPropagateVolumeSelection="1" ></SliceComposite>
 <SubjectHierarchy
  id="vtkMRMLSubjectHierarchyNode1" name="SubjectHierarchy" hideFromEditors="false" selectable="true" selected="false" attributes="SubjectHierarchyVersion:2" >
   <SubjectHierarchyItem id="3" name="Scene" parent="0" type="" expanded="true" attributes="Level^Scene|">
   <SubjectHierarchyItem id="9" dataNode="vtkMRMLLabelMapVolumeNode1" parent="3" type="LabelMaps" expanded="true"></SubjectHierarchyItem>
   <SubjectHierarchyItem id="10" dataNode="vtkMRMLScalarVolumeNode1" parent="3" type="Volumes" expanded="true"></SubjectHierarchyItem></SubjectHierarchyItem></SubjectHierarchy>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeYellow" name="SliceComposite_2" hideFromEditors="true" selectable="true" selected="false" singletonTag="Yellow" references="backgroundVolume:vtkMRMLScalarVolumeNode1;labelVolume:vtkMRMLLabelMapVolumeNode1;" compositing="0" foregroundOpacity="0" labelOpacity="0.5" linkedControl="1" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Yellow" doPropagateVolumeSelection="1" ></SliceComposite>
 <ColorTableStorage
  id="vtkMRMLColorTableStorageNode22" name="ColorTableStorage" hideFromEditors="true" selectable="true" selected="false" fileName="bounti-19.txt" useCompression="1" defaultWriteFileExtension="ctbl" readState="0" writeState="4" ></ColorTableStorage>
 <ColorTable
  id="vtkMRMLColorTableNode1" name="bounti-19" description="A color table read in from a text file, each line of the format: IntegerLabel  Name  R  G  B  Alpha" hideFromEditors="false" selectable="true" selected="false" attributes="Category:File" references="storage:vtkMRMLColorTableStorageNode22;" userTags="" type="14" numcolors="20" ></ColorTable>
 <LabelMapVolumeDisplay
  id="vtkMRMLLabelMapVolumeDisplayNode1" name="LabelMapVolumeDisplay" hideFromEditors="true" selectable="true" selected="false" color="0.9 0.9 0.3" edgeColor="0 0 0" selectedColor="1 0 0" selectedAmbient="0.4" ambient="0" diffuse="1" selectedSpecular="0.5" specular="0" power="1" metallic="0" roughness="0.5" opacity="1" sliceIntersectionOpacity="1" pointSize="1" lineWidth="1" representation="2" lighting="true" interpolation="1" shading="true" visibility="false" visibility2D="false" visibility3D="true" edgeVisibility="false" clipping="false" sliceIntersectionThickness="3" frontfaceCulling="false" backfaceCulling="false" scalarVisibility="false" vectorVisibility="false" tensorVisibility="false" interpolateTexture="false" scalarRangeFlag="UseData" scalarRange="0 100" colorNodeID="vtkMRMLColorTableNode1" activeAttributeLocation="point" viewNodeRef="" folderDisplayOverrideAllowed="true" ></LabelMapVolumeDisplay>
 <VolumeArchetypeStorage
  id="vtkMRMLVolumeArchetypeStorageNode3" name="VolumeArchetypeStorage_2" hideFromEditors="true" selectable="true" selected="false" fileName="reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19.nii.gz" useCompression="1" defaultWriteFileExtension="nrrd" readState="0" writeState="0" centerImage="0" UseOrientationFromFile="1" ></VolumeArchetypeStorage>
 <LabelMapVolume
  id="vtkMRMLLabelMapVolumeNode1" name="reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19" hideFromEditors="false" selectable="true" selected="false" references="display:vtkMRMLLabelMapVolumeDisplayNode1 vtkMRMLColorLegendDisplayNode1;storage:vtkMRMLVolumeArchetypeStorageNode3;" userTags="" spacing="0.4 0.4 0.4" origin="67.4 -67 -62.6" voxelVectorType="undefined" ijkToRASDirections="-1   0   0 0   1   0 0 0 1 " ></LabelMapVolume>
 <VolumeDisplay
  id="vtkMRMLScalarVolumeDisplayNode1" name="VolumeDisplay" hideFromEditors="true" selectable="true" selected="false" color="0.9 0.9 0.3" edgeColor="0 0 0" selectedColor="1 0 0" selectedAmbient="0.4" ambient="0" diffuse="1" selectedSpecular="0.5" specular="0" power="1" metallic="0" roughness="0.5" opacity="1" sliceIntersectionOpacity="1" pointSize="1" lineWidth="1" representation="2" lighting="true" interpolation="1" shading="true" visibility="true" visibility2D="false" visibility3D="true" edgeVisibility="false" clipping="false" sliceIntersectionThickness="1" frontfaceCulling="false" backfaceCulling="false" scalarVisibility="false" vectorVisibility="false" tensorVisibility="false" interpolateTexture="false" scalarRangeFlag="UseData" scalarRange="0 100" colorNodeID="vtkMRMLColorTableNodeGrey" activeAttributeLocation="point" viewNodeRef="" folderDisplayOverrideAllowed="true" window="1108.95" level="554.477" upperThreshold="32767" lowerThreshold="-32768" interpolate="1" autoWindowLevel="1" applyThreshold="0" autoThreshold="0" ></VolumeDisplay>
 <VolumeArchetypeStorage
  id="vtkMRMLVolumeArchetypeStorageNode4" name="VolumeArchetypeStorage_3" hideFromEditors="true" selectable="true" selected="false" fileName="reo-SVR-output-brain-n4corr-hires.nii.gz" useCompression="1" defaultWriteFileExtension="nrrd" readState="0" writeState="0" centerImage="0" UseOrientationFromFile="1" ></VolumeArchetypeStorage>
 <Volume
  id="vtkMRMLScalarVolumeNode1" name="reo-SVR-output-brain-n4corr-hires" hideFromEditors="false" selectable="true" selected="false" references="display:vtkMRMLScalarVolumeDisplayNode1;storage:vtkMRMLVolumeArchetypeStorageNode4;" userTags="" spacing="0.4 0.4 0.4" origin="67.4 -67 -62.6" voxelVectorType="undefined" ijkToRASDirections="-1   0   0 0   1   0 0 0 1 " ></Volume>
 <ColorLegendDisplay
  id="vtkMRMLColorLegendDisplayNode1" name="reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19 color legend" hideFromEditors="true" selectable="true" selected="false" references="primaryDisplay:vtkMRMLLabelMapVolumeDisplayNode1;" color="0.9 0.9 0.3" edgeColor="0 0 0" selectedColor="1 0 0" selectedAmbient="0.4" ambient="0" diffuse="1" selectedSpecular="0.5" specular="0" power="1" metallic="0" roughness="0.5" opacity="1" sliceIntersectionOpacity="1" pointSize="1" lineWidth="1" representation="2" lighting="true" interpolation="1" shading="true" visibility="true" visibility2D="true" visibility3D="true" edgeVisibility="false" clipping="false" sliceIntersectionThickness="1" frontfaceCulling="false" backfaceCulling="false" scalarVisibility="false" vectorVisibility="false" tensorVisibility="false" interpolateTexture="false" scalarRangeFlag="UseData" scalarRange="0 100" activeAttributeLocation="point" viewNodeRef="" folderDisplayOverrideAllowed="true" orientation="Vertical" position="0.95 0.9" size="0.15 0.5" titleText="BOUNTI-19" titleTextProperty="font-family:Arial;font-size:12px;font-style:normal;font-weight:normal;color:rgba(255,255,255,1);background-color:rgba(0,0,0,0);border-width:1px;border-color:rgba(255,255,255,0.0);text-shadow:1px -1px 2px rgba(0,0,0,1.0);" labelTextProperty="font-family:Arial;font-size:13px;font-style:normal;font-weight:normal;color:rgba(255,255,255,1);background-color:rgba(0,0,0,0);border-width:1px;border-color:rgba(255,255,255,0.0);text-shadow:1px -1px 2px rgba(0,0,0,1.0);" labelFormat="%s" maxNumberOfColors="19" numberOfLabels="19" useColorNamesForLabels="true" ></ColorLegendDisplay>
</MRML>
EOF

# Set File Permissions
chmod 0775 -R $OUT_DIR

mv ./slurm-$SLURM_JOBID.out /hpf/projects/cmacgowan/jcosma/4DCardiac/$CASE/SLURM/1-MATLAB-Preproc-i-$SLURM_JOBID.out

# End
echo -e "\n\n=== TRANSIT CHD Brain Structural Pipeline (Basic) Complete =====================\n\n"