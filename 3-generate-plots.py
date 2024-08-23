import os
import matplotlib.pyplot as plt
import pandas as pd

# Function to generate and save scatter plots
def generate_scatter_plots(data, output_dir):
    measures = data['Measure']
    for index, measure in enumerate(measures):
        values = data.iloc[index, 1:]  # Get values for this measure across all columns
        plt.figure()
        plt.scatter(range(len(values)), values, marker='o')
        plt.xlabel('Files')
        plt.ylabel('Volume')
        plt.title(f'{measure} Volume Comparison')
        plt.xticks(ticks=range(len(values.index)), labels=values.index, rotation=45)
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, f'{measure}_volume_comparison.png'))
        plt.close()

# Main script
def main():
    # Specify the input file path
    csv_file = 'combined_volumes.csv'
    
    # Check if the file exists
    if not os.path.isfile(csv_file):
        print(f"File {csv_file} does not exist.")
        return
    
    # Read the CSV file
    data = pd.read_csv(csv_file)
    
    # Output directory for plots
    output_dir = 'csv_volume_plots'
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate scatter plots
    generate_scatter_plots(data, output_dir)
    
    print(f"Scatter plots saved in directory: {output_dir}")

if __name__ == "__main__":
    main()
