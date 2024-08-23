#!/bin/bash

# Define the file path
input_volumes="measure-volume.txt"
output_volumes="calc-volumes.txt"

# Initialize an array with 0.0 values
declare -a orderedVals=(0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)

# Read the file and extract integers into an indexed array
mapfile -t inLabels < <(awk '{print $1}' "$input_volumes")
mapfile -t inVals < <(awk '{print $2}' "$input_volumes")

# Order values in array
for i in $(seq 0 18); do
    X=$((${inLabels[$i]} - 1))
    if [ "$X" -ge 0 ] && [ "$X" -lt 19 ]; then
        orderedVals[$X]=${inVals[$i]}
    else
        echo "Warning: Invalid index $X derived from label ${inLabels[$i]} at line $((i+1)). Skipping."
    fi
done

# Values
cGML=${orderedVals[2]}
cGMR=${orderedVals[3]}
WML=${orderedVals[4]}
WMR=${orderedVals[5]}
THALL=${orderedVals[15]}
THALR=${orderedVals[16]}
GANGL=${orderedVals[13]}
GANGR=${orderedVals[14]}
CERL=${orderedVals[10]}
CERR=${orderedVals[11]}
CERV=${orderedVals[12]}
ECSFL=${orderedVals[0]}
ECSFR=${orderedVals[1]}
LVENTL=${orderedVals[6]}
LVENTR=${orderedVals[7]}
CAV=${orderedVals[8]}
TVENT=${orderedVals[17]}
FVENT=${orderedVals[18]:-0.0}  # Default to 0.0 if not set
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
} > "$output_volumes"

