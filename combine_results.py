import csv
import os
import sys

#run file with number of inputs as first argument and paths to files as subsequent arguments
#ex: python3 combine_results.py combined_metrics.csv case1/svr/metrics.txt case2/svr/metrics.txt case3/svr/metrics.txt

def parse_file(file_path):
    values = {}
    with open(file_path, 'r') as file:
        for line in file:
            parts = line.split()
            if len(parts) == 2:
                measure, value = parts
                values[measure] = float(value)
    return values

# Main script
def main():

    # Get output file
    output_file = sys.argv[1]
    
    # Get number of files
    num_files = int(len(sys.argv)-2)
    
    # Dictionary to hold combined data
    combined_data = []
    for i in range(num_files):
        file_path = sys.argv[i+2]
        # Ensure the file exists
        if not os.path.isfile(file_path):
            print(f"File {file_path} does not exist. Skipping...")
            continue
        # Parse the file and add to combined data
        data = {}
        data['filepath'] = file_path
        data.update(parse_file(file_path))
        combined_data.append(data)
    
    # Writing to CSV
    with open(output_file, 'w', newline='') as csvfile:
        fieldnames = list(combined_data[0].keys())
        csvwriter = csv.DictWriter(csvfile, fieldnames=fieldnames)
        csvwriter.writeheader()
        csvwriter.writerows(combined_data)    
    print(f"Data written to {output_file}")

if __name__ == "__main__":
    main()