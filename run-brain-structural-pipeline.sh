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
Usage: $(basename "${BASH_SOURCE[0]}") TBD

Run basic TRANSIT CHD structural brain pipeline: preprocessing, SVR, BOUNTI and reporting 

Requires directory with input files bound to /home/data/input, output directory bound to /home/data/output and temp directory bound to /home/tmp_proc. 

Example container usage:
  singularity exec --bind \$INPUT_DIR:/home/data/input,\$OUTPUT_DIR:/home/data/output,\$TEMP_DIR:/home/tmp_proc svrtk-auto.sif /bin/sh -c "/home/scripts/run-brain-structural-pipeline.sh \$STACK_SLICE_THICKNESS"

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
VIEW_DIR=$OUT_DIR/view-result

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
echo -e "\n\n=== 05 Calculate Label Volumes =================================================\n\n"
set -x
mirtk measure-volume $SEG_DIR/reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19.nii.gz > $SEG_DIR/measure-volume.txt
{ set +x; } 2>/dev/null

# Create Slicer View File
echo -e "\n\n=== 06 Creating Slicer View File =================================================\n\n"
set -x
mkdir $VIEW_DIR
#copy files into folder and rename them
#note that file names must match names in MRML file
cp $SEG_DIR/reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19.nii.gz $VIEW_DIR
mv $VIEW_DIR/reo-SVR-output-brain-n4corr-hires-mask-brain_bounti-19.nii.gz $VIEW_DIR/BOUNTI-SEG.nii.gz
cp $VOLUME_DIR/reo-SVR-output-brain-n4corr-hires.nii.gz $VIEW_DIR
mv $VIEW_DIR/reo-SVR-output-brain-n4corr-hires.nii.gz $VIEW_DIR/SVR-OUTPUT.nii.gz
#Generate Slicer view
cat > $VIEW_DIR/VIEW-RESULT.mrml << EOF

<?xml version="1.0" encoding="UTF-8"?>
<MRML version="Slicer 5.6.1 32438" userTags="">
<Crosshair
  id="vtkMRMLCrosshairNodedefault" name="Crosshair" hideFromEditors="true" selectable="true" selected="false" singletonTag="default" crosshairMode="NoCrosshair" crosshairBehavior="OffsetJumpSlice" crosshairThickness="Fine" crosshairRAS="0 0 0"></Crosshair>
 <Selection
  id="vtkMRMLSelectionNodeSingleton" name="Selection" hideFromEditors="true" selectable="true" selected="false" singletonTag="Singleton" references="ActiveVolume:vtkMRMLScalarVolumeNode2;unit/area:vtkMRMLUnitNodeApplicationArea;unit/frequency:vtkMRMLUnitNodeApplicationFrequency;unit/intensity:vtkMRMLUnitNodeApplicationIntensity;unit/length:vtkMRMLUnitNodeApplicationLength;unit/time:vtkMRMLUnitNodeApplicationTime;unit/velocity:vtkMRMLUnitNodeApplicationVelocity;unit/volume:vtkMRMLUnitNodeApplicationVolume;" ></Selection>
 <Interaction
  id="vtkMRMLInteractionNodeSingleton" name="Interaction" hideFromEditors="true" selectable="true" selected="false" singletonTag="Singleton" currentInteractionMode="ViewTransform" placeModePersistence="false" lastInteractionMode="ViewTransform" ></Interaction>
 <View
  id="vtkMRMLViewNode1" name="View1" hideFromEditors="false" selectable="true" selected="false" singletonTag="1" attributes="MappedInLayout:1" layoutLabel="1" layoutName="1" active="false" visibility="true" backgroundColor="0.756863 0.764706 0.909804" backgroundColor2="0.454902 0.470588 0.745098" layoutColor="0.454902 0.513725 0.913725" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="200" letterSize="0.05" boxVisible="true" boxColor="1 0 1" fiducialsVisible="true" fiducialLabelsVisible="true" axisLabelsVisible="true" axisLabelsCameraDependent="true" animationMode="Off" viewAxisMode="LookFrom" spinDegrees="2" spinMs="5" spinDirection="YawLeft" rotateDegrees="5" rockLength="200" rockCount="0" stereoType="NoStereo" renderMode="Perspective" useDepthPeeling="1" gpuMemorySize="0" autoReleaseGraphicsResources="false" expectedFPS="8" volumeRenderingQuality="Normal" raycastTechnique="Composite" volumeRenderingSurfaceSmoothing="0" volumeRenderingOversamplingFactor="2" linkedControl="0" ></View>
 <Slice
  id="vtkMRMLSliceNodeRed" name="Red" hideFromEditors="false" selectable="true" selected="false" singletonTag="Red" attributes="MappedInLayout:1" layoutLabel="R" layoutName="Red" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.952941 0.290196 0.2" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="215.657 122.4 0.4" dimensions="592 336 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="215.657 122.4 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="-1 0 0 2.8 0 1 0 -1.2 0 0 1 4.2 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Axial" defaultOrientation="Axial" orientationReference="Axial" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <Slice
  id="vtkMRMLSliceNodeGreen" name="Green" hideFromEditors="false" selectable="true" selected="false" singletonTag="Green" attributes="MappedInLayout:1" layoutLabel="G" layoutName="Green" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.431373 0.690196 0.294118" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="187.467 106.4 0.4" dimensions="592 336 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="187.467 106.4 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="-1 0 0 2.8 0 0 1 -1 0 1 0 4 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Coronal" defaultOrientation="Coronal" orientationReference="Coronal" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <Slice
  id="vtkMRMLSliceNodeYellow" name="Yellow" hideFromEditors="false" selectable="true" selected="false" singletonTag="Yellow" attributes="MappedInLayout:1" layoutLabel="Y" layoutName="Yellow" active="false" visibility="true" backgroundColor="0 0 0" backgroundColor2="0 0 0" layoutColor="0.929412 0.835294 0.298039" orientationMarkerType="none" orientationMarkerSize="medium" rulerType="none" rulerColor="white" AxisLabels="L;R;P;A;I;S" fieldOfView="186.833 106.4 0.4" dimensions="590 336 1" xyzOrigin="0 0 0" sliceResolutionMode="1" uvwExtents="186.833 106.4 0.4" uvwDimensions="256 256 1" uvwOrigin="0 0 0" activeSlice="0" layoutGridRows="1" layoutGridColumns="1" sliceToRAS="0 0 -1 2.6 -1 0 0 -1.2 0 1 0 4 0 0 0 1" orientationMatrixAxial="-1 0 0 0 1 0 0 0 1" orientationMatrixSagittal="0 0 -1 -1 0 0 0 1 0" orientationMatrixCoronal="-1 0 0 0 0 1 0 1 0" orientation="Sagittal" defaultOrientation="Sagittal" orientationReference="Sagittal" jumpMode="1" sliceVisibility="false" widgetVisibility="false" widgetOutlineVisibility="true" useLabelOutline="false" sliceSpacingMode="0" prescribedSliceSpacing="1 1 1" slabReconstructionEnabled="false" slabReconstructionType="Max" slabReconstructionThickness="1" slabReconstructionOversamplingFactor="2" ></Slice>
 <Layout
  id="vtkMRMLLayoutNodevtkMRMLLayoutNode" name="Layout" hideFromEditors="true" selectable="true" selected="false" singletonTag="vtkMRMLLayoutNode" currentViewArrangement="3" guiPanelVisibility="1" bottomPanelVisibility ="1" guiPanelLR="0" collapseSliceControllers="0"
 numberOfCompareViewRows="1" numberOfCompareViewColumns="1" numberOfLightboxRows="6" numberOfLightboxColumns="6" mainPanelSize="400" secondaryPanelSize="400" ></Layout>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeRed" name="SliceComposite" hideFromEditors="true" selectable="true" selected="false" singletonTag="Red" references="backgroundVolume:vtkMRMLScalarVolumeNode2;foregroundVolume:vtkMRMLScalarVolumeNode1;" compositing="0" foregroundOpacity="0.5" labelOpacity="1" linkedControl="0" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Red" doPropagateVolumeSelection="1" ></SliceComposite>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeGreen" name="SliceComposite_1" hideFromEditors="true" selectable="true" selected="false" singletonTag="Green" references="backgroundVolume:vtkMRMLScalarVolumeNode2;foregroundVolume:vtkMRMLScalarVolumeNode1;" compositing="0" foregroundOpacity="0.5" labelOpacity="1" linkedControl="0" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Green" doPropagateVolumeSelection="1" ></SliceComposite>
 <SubjectHierarchy
  id="vtkMRMLSubjectHierarchyNode1" name="SubjectHierarchy" hideFromEditors="false" selectable="true" selected="false" attributes="SubjectHierarchyVersion:2" >
   <SubjectHierarchyItem id="3" name="Scene" parent="0" type="" expanded="true" attributes="Level^Scene|">
     <SubjectHierarchyItem id="9" dataNode="vtkMRMLScalarVolumeNode1" parent="3" type="Volumes" expanded="true"></SubjectHierarchyItem>
     <SubjectHierarchyItem id="12" dataNode="vtkMRMLScalarVolumeNode2" parent="3" type="Volumes" expanded="true"></SubjectHierarchyItem></SubjectHierarchyItem></SubjectHierarchy>
 <SliceComposite
  id="vtkMRMLSliceCompositeNodeYellow" name="SliceComposite_2" hideFromEditors="true" selectable="true" selected="false" singletonTag="Yellow" references="backgroundVolume:vtkMRMLScalarVolumeNode2;foregroundVolume:vtkMRMLScalarVolumeNode1;" compositing="0" foregroundOpacity="0.5" labelOpacity="1" linkedControl="0" hotLinkedControl="0" fiducialVisibility="1" fiducialLabelVisibility="1" layoutName="Yellow" doPropagateVolumeSelection="1" ></SliceComposite>
 <Camera
  id="vtkMRMLCameraNode1" name="Camera" description="Default Scene Camera" hideFromEditors="false" selectable="true" selected="false" singletonTag="1" userTags="" position="0 500 0" focalPoint="0 0 0" viewUp="0 0 1" parallelProjection="false" parallelScale="1" viewAngle="30" appliedTransform="1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1" ></Camera>
 <ClipModels
  id="vtkMRMLClipModelsNodevtkMRMLClipModelsNode" name="ClipModels" hideFromEditors="true" selectable="true" selected="false" singletonTag="vtkMRMLClipModelsNode" clipType="0" redSliceClipState="0" yellowSliceClipState="0" greenSliceClipState="0" ></ClipModels>
 <ScriptedModule
  id="vtkMRMLScriptedModuleNodeDataProbe" name="ScriptedModule" hideFromEditors="true" selectable="true" selected="false" singletonTag="DataProbe" ModuleName ="DataProbe" ></ScriptedModule>
 <VolumeDisplay
  id="vtkMRMLScalarVolumeDisplayNode1" name="VolumeDisplay" hideFromEditors="true" selectable="true" selected="false" color="0.9 0.9 0.3" edgeColor="0 0 0" selectedColor="1 0 0" selectedAmbient="0.4" ambient="0" diffuse="1" selectedSpecular="0.5" specular="0" power="1" metallic="0" roughness="0.5" opacity="1" sliceIntersectionOpacity="1" pointSize="1" lineWidth="1" representation="2" lighting="true" interpolation="1" shading="true" visibility="true" visibility2D="false" visibility3D="true" edgeVisibility="false" clipping="false" sliceIntersectionThickness="1" frontfaceCulling="false" backfaceCulling="false" scalarVisibility="false" vectorVisibility="false" tensorVisibility="false" interpolateTexture="false" scalarRangeFlag="UseData" scalarRange="0 100" colorNodeID="vtkMRMLColorTableNodeRandom" activeAttributeLocation="point" viewNodeRef="" folderDisplayOverrideAllowed="true" window="16.9998" level="8.49992" upperThreshold="32767" lowerThreshold="-32768" interpolate="0" autoWindowLevel="1" applyThreshold="0" autoThreshold="0" ></VolumeDisplay>
 <VolumeArchetypeStorage
  id="vtkMRMLVolumeArchetypeStorageNode4" name="VolumeArchetypeStorage_3" hideFromEditors="true" selectable="true" selected="false" fileName="BOUNTI-SEG.nii.gz" useCompression="1" defaultWriteFileExtension="nrrd" readState="0" writeState="0" centerImage="0" UseOrientationFromFile="1" ></VolumeArchetypeStorage>
 <Volume
  id="vtkMRMLScalarVolumeNode1" name="BOUNTI-SEG" hideFromEditors="false" selectable="true" selected="false" references="display:vtkMRMLScalarVolumeDisplayNode1;storage:vtkMRMLVolumeArchetypeStorageNode4;" userTags="" spacing="0.4 0.4 0.4" origin="55.4 -62.2 -49" voxelVectorType="undefined" ijkToRASDirections="-1   0   0 0   1   0 0 0 1 " ></Volume>
 <VolumeDisplay
  id="vtkMRMLScalarVolumeDisplayNode2" name="VolumeDisplay" hideFromEditors="true" selectable="true" selected="false" color="0.9 0.9 0.3" edgeColor="0 0 0" selectedColor="1 0 0" selectedAmbient="0.4" ambient="0" diffuse="1" selectedSpecular="0.5" specular="0" power="1" metallic="0" roughness="0.5" opacity="1" sliceIntersectionOpacity="1" pointSize="1" lineWidth="1" representation="2" lighting="true" interpolation="1" shading="true" visibility="true" visibility2D="false" visibility3D="true" edgeVisibility="false" clipping="false" sliceIntersectionThickness="1" frontfaceCulling="false" backfaceCulling="false" scalarVisibility="false" vectorVisibility="false" tensorVisibility="false" interpolateTexture="false" scalarRangeFlag="UseData" scalarRange="0 100" colorNodeID="vtkMRMLColorTableNodeGrey" activeAttributeLocation="point" viewNodeRef="" folderDisplayOverrideAllowed="true" window="1369.59" level="627.309" upperThreshold="32767" lowerThreshold="-32768" interpolate="1" autoWindowLevel="1" applyThreshold="0" autoThreshold="0" ></VolumeDisplay>
 <VolumeArchetypeStorage
  id="vtkMRMLVolumeArchetypeStorageNode2" name="VolumeArchetypeStorage_3" hideFromEditors="true" selectable="true" selected="false" fileName="SVR-OUTPUT.nii.gz" useCompression="1" defaultWriteFileExtension="nrrd" readState="0" writeState="0" centerImage="0" UseOrientationFromFile="1" ></VolumeArchetypeStorage>
 <Volume
  id="vtkMRMLScalarVolumeNode2" name="SVR-OUTPUT" hideFromEditors="false" selectable="true" selected="false" references="display:vtkMRMLScalarVolumeDisplayNode2;storage:vtkMRMLVolumeArchetypeStorageNode2;" userTags="" spacing="0.4 0.4 0.4" origin="55.4 -62.2 -49" voxelVectorType="undefined" ijkToRASDirections="-1   0   0 0   1   0 0 0 1 " ></Volume>
</MRML>


EOF

# Set File Permissions
chmod 0775 -R $OUT_DIR

# End
echo -e "\n\n=== TRANSIT CHD Brain Structural Pipeline (Basic) Complete =====================\n\n"