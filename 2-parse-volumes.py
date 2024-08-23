import csv
import os
import sys

#run file with number of inputs as first argument and paths to files as subsequent arguments
#ex: python parse-volumes.py 2 ./path/calc-volumes.txt ./path/calc-volumes.txt 

def parse_volumes(file_path):
    volumes = {}
    with open(file_path, 'r') as file:
        for line in file:
            parts = line.split()
            if len(parts) == 2:
                measure, value = parts
                volumes[measure] = float(value)
    return volumes

# Main script
def main():
    # Get number of files
    num_files = int(sys.argv[1])
    
    # Dictionary to hold combined data
    combined_data = {}
    
    for i in range(num_files):
        file_path = sys.argv[i+2]        
        # Ensure the file exists
        if not os.path.isfile(file_path):
            print(f"File {file_path} does not exist. Skipping...")
            continue
        
        # Parse the file and add to combined data
        volumes = parse_volumes(file_path)
        for measure, value in volumes.items():
            if measure in combined_data:
                combined_data[measure].append(value)
            else:
                combined_data[measure] = [value]
    
    # Prepare to write to CSV
    output_file = 'combined_volumes.csv'
    
    # Writing to CSV
    with open(output_file, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile)
        
        # Write the header
        header = ['Measure'] + [f'File_{i+1}' for i in range(num_files)]
        csvwriter.writerow(header)
        
        # Write the data
        for measure, values in combined_data.items():
            row = [measure] + values
            csvwriter.writerow(row)
    
    print(f"Data written to {output_file}")

if __name__ == "__main__":
    main()
