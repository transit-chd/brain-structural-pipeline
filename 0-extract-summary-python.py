import re
import csv
import sys

# Input and output file paths
#input_file = str(sys.argv[1])
input_file = "slurm-12084883.out"
svr_text_sum = "out/04_bounti/SVR-Summary.txt"
svr_csv_sum = "out/04_bounti/SVR-Summary-Table.csv"

# Initialize variables to store the extracted information
stack_selection_exclusion = []
slice_normalized_cross_correlation = []
stack_metrics = []

# Read the input file line by line
with open(input_file, 'r') as file:
    capture_metrics = False
    for line in file:
        # Extract stacselectionk  and exclusion
        if re.search(r'stack \d+', line) and 'excluded' in line:
            stack_selection_exclusion.append(line.strip())

        # Extract slice normalized cross correlation
        if 'ncc' in line and not capture_metrics:
            slice_normalized_cross_correlation.append(line.strip())

        # Start capturing stack metrics
        if 'Stack metrics' in line:
            capture_metrics = True

        # Capture the lines related to stack metrics
        if capture_metrics:
            stack_metrics.append(line.strip())
            if 'Generated' in line: 
                capture_metrics = False

# Write the extracted information to the output file
with open(svr_text_sum, 'w') as file:
    file.write("Summary of Stack Selection and Exclusion:\n")
    file.write("\n".join(stack_selection_exclusion) + "\n")
    file.write("*note that stacks are renumbered from 0 after this exclusion step\n")
    file.write("Global Metrics for Each Iteration (0-3):\n")
    file.write("\n".join(slice_normalized_cross_correlation) + "\n\n")
    file.write("Stack Metrics:\n")
    file.write("\n".join(stack_metrics) + "\n")

print(f"Summary written to {svr_text_sum}")


#--------- CSV Part ---------

# Input file path
input_file = svr_text_sum


# Initialize variables to store the extracted information
# ncc = 0.0
# nrmse = 0.0
# average_weight = 0.0
# excluded_slices = 0.0

print("test!!")

# Read the input file line by line
with open(input_file, 'r') as file:
    capture_stack_metrics = False
    for line in file:
        # Extract excluded stack numbers
        if re.match(r'^\s*-\s*global metrics:', line):
            print("match!!!")
            ncc_match = re.search(r'ncc\s*=\s*([0-9]*\.[0-9]+)', line)
            nrmse_match = re.search(r'nrmse\s*=\s*([0-9]*\.[0-9]+)', line)
            average_weight_match = re.search(r'average weight\s*=\s*([0-9]*\.[0-9]+)', line)
            excluded_slices_match = re.search(r'excluded slices\s*=\s*([0-9]*\.[0-9]+)', line)

            ncc = float(ncc_match.group(1)) if ncc_match else None
            nrmse = float(nrmse_match.group(1)) if nrmse_match else None
            average_weight = float(average_weight_match.group(1)) if average_weight_match else None
            excluded_slices = float(excluded_slices_match.group(1)) if excluded_slices_match else None

data = [
    ["NCC", ncc],
    ["NRMSE",nrmse], 
    ["Average Weight",average_weight], 
    ["Excluded Slices",excluded_slices],
]

# Write the extracted information to the CSV file
with open(svr_csv_sum, 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerows(data)


print(f"CSV summary written to {svr_csv_sum}")

#-----------VOLUMES-----------------
input_file = "out/04_bounti/calc-volumes.txt"
vol_table = "out/04_bounti/calculated-volumes-table.csv"

# Regular expression to match numbers (both integers and decimals)
number_pattern = r'([0-9]+(?:\.[0-9]+)?)'

# Read the input file line by line
with open(input_file, 'r') as file:
    for line in file:
        # Extract cGM
        if "cGM" in line:
            cgm_match = re.search(r'cGM\s*' + number_pattern, line)
            cgm = float(cgm_match.group(1)) if cgm_match else None
        # Extract WM
        elif "WM" in line:
            wm_match = re.search(r'WM\s*' + number_pattern, line)
            wm = float(wm_match.group(1)) if wm_match else None
        # Extract dGM
        elif "dGM" in line:
            dgm_match = re.search(r'dGM\s*' + number_pattern, line)
            dgm = float(dgm_match.group(1)) if dgm_match else None
        # Extract CER
        elif "CER" in line:
            cer_match = re.search(r'CER\s*' + number_pattern, line)
            cer = float(cer_match.group(1)) if cer_match else None
        # Extract CSF
        elif "CSF" in line:
            csf_match = re.search(r'CSF\s*' + number_pattern, line)
            csf = float(csf_match.group(1)) if csf_match else None
        # Extract TBV
        elif "TBV" in line:
            tbv_match = re.search(r'TBV\s*' + number_pattern, line)
            tbv = float(tbv_match.group(1)) if tbv_match else None

#
data = [
    ["Cortical Grey Matter", cgm],
    ["White Matter",wm], 
    ["Deep Grey Matter",dgm], 
    ["Cerebellum",cer], 
    ["Total Cerebral Spinal Fluid",csf],
    ["Total Brain Volume",tbv],
]

# Write the extracted information to the CSV file
with open(vol_table, 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerows(data)

print(f"Results printed to {vol_table}")