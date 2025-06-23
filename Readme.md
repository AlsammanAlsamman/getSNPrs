# getSNPrs - Fast SNP Lookup Tool

A high-performance bash-based tool for searching SNPs in reference VCF files based on chromosome and position coordinates. The tool supports parallel processing for large datasets and handles various chromosome naming conventions.

## Features

- **Optimized output format**: Returns essential fields (chr, pos, rsid, ref, alt) by default
- **Custom INFO fields**: Add specific VCF INFO fields as needed (e.g., AC, AF, DP)
- **Missing data handling**: Returns "." for missing SNPs with all requested fields
- **Comprehensive reporting**: Detailed reports with statistics and missing SNP warnings
- **Fast parallel processing**: Automatically splits large files (>1000 SNPs) for parallel processing
- **Flexible chromosome formats**: Supports both numeric (1, 2, 3...) and chr-prefixed formats (chr1, chr2, chr3...)
- **Sex chromosome handling**: Automatically converts between numeric (23, 24, 25) and standard (X, Y, MT) formats
- **Automatic delimiter detection**: Detects space or tab delimiters in input files
- **Customizable output**: Choose between tab or space-separated output
- **Reference file management**: Automatically downloads reference files if not provided
- **Memory efficient**: Processes files in chunks to handle large datasets

## Installation

### Prerequisites

The following tools are required:
- `bcftools` (for VCF file querying)
- `wget` (for downloading reference files)
- `gunzip` (for file decompression)
- `sort` and `uniq` (standard Unix tools)

#### Installing bcftools

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install bcftools
```

**CentOS/RHEL:**
```bash
sudo yum install bcftools
# or for newer versions:
sudo dnf install bcftools
```

**macOS:**
```bash
brew install bcftools
```

**From source:**
```bash
wget https://github.com/samtools/bcftools/releases/download/1.17/bcftools-1.17.tar.bz2
tar -xjf bcftools-1.17.tar.bz2
cd bcftools-1.17
make
sudo make install
```

### Installing getSNPrs

1. Clone or download the repository:
```bash
git clone https://github.com/yourusername/getSNPrs.git
cd getSNPrs
```

2. Make the script executable:
```bash
chmod +x getSNPrs.sh
```

3. Optionally, add to your PATH:
```bash
# Add to ~/.bashrc or ~/.profile
export PATH="/path/to/getSNPrs:$PATH"
```

## Usage

### Basic Syntax
```bash
./getSNPrs.sh [OPTIONS] -i INPUT_FILE
```

### Options

| Option | Long Form | Description | Default |
|--------|-----------|-------------|---------|
| `-i` | `--input` | Input file with chromosome and position (required) | - |
| `-o` | `--output` | Output file | stdout |
| `-r` | `--reference` | Reference VCF file | auto-download |
| `-t` | `--threads` | Number of threads for parallel processing | 4 |
| `-b` | `--build` | Genome build (only hg19 supported) | hg19 |
| `-d` | `--delimiter` | Input delimiter: 'tab', 'space', or 'auto' | auto |
| `-D` | `--output-delimiter` | Output delimiter: 'tab', 'space', or 'auto' | auto |
| `-s` | `--split-size` | Number of SNPs per chunk for parallel processing | 1000 |
| `-I` | `--info` | Additional INFO fields to include (comma-separated) | none |
| `-R` | `--report` | Generate report file | auto-generated name |
| `` | `--no-report` | Disable report generation | false |
| `-q` | `--quiet` | Suppress informational messages | false |
| `-h` | `--help` | Show help message | - |

### Input File Format

The input file should contain chromosome and position coordinates, one per line, separated by space or tab:

#### Supported formats:

**Chr-prefixed format:**
```
chr1    998371
chr2    954000
chrX    123456
chrY    789012
chrMT   16569
```

**Numeric format:**
```
1       998371
2       954000
23      123456
24      789012
25      16569
```

**Mixed content (optional third column ignored):**
```
chr1    998371  rs123456
2       954000  some_annotation
```

### Examples

#### Basic usage with default output format:
```bash
./getSNPrs.sh -i my_snps.txt
```

#### Include additional INFO fields (allele count, frequency, depth):
```bash
./getSNPrs.sh -i my_snps.txt --info "AC,AF,DP"
```

#### Save output to file with 8 threads:
```bash
./getSNPrs.sh -i my_snps.txt -o results.txt -t 8
```

#### Generate a custom report:
```bash
./getSNPrs.sh -i my_snps.txt -o results.txt --report detailed_report.txt
```

#### Disable report generation:
```bash
./getSNPrs.sh -i my_snps.txt --no-report
```

#### Use custom reference file:
```bash
./getSNPrs.sh -i my_snps.txt -r my_custom_reference.vcf.gz -o results.txt
```

#### Specify delimiters explicitly:
```bash
./getSNPrs.sh -i my_snps.txt -d tab -D space -o results.txt
```

#### Process large file with custom chunk size:
```bash
./getSNPrs.sh -i large_snp_list.txt -s 5000 -t 8 -o results.txt
```

#### Silent mode (no progress messages):
```bash
./getSNPrs.sh -i my_snps.txt -o results.txt -q
```

### Output Format

#### Default Output Format
The default output contains essential SNP information:
```
CHROM   POS     ID      REF     ALT
chr1    998371  .       A       G
chr1    998395  rs7526076       A       G
chr2    12345   .       .       .
```

#### With Additional INFO Fields
When using `--info` option:
```
CHROM   POS     ID      REF     ALT     AC      AF      DP
chr1    998371  .       A       G       6       0.0106  1391
chr1    998395  rs7526076       A       G       1449    0.80679 4351
chr2    12345   .       .       .       .       .       .
```

#### Missing SNPs
SNPs not found in the reference will have "." for missing fields:
- Position exists but no variant: All fields except CHROM and POS will be "."
- Position doesn't exist: All fields except CHROM and POS will be "."

The chromosome format in the output will match your input format:
- Input `chr1` → Output `chr1`
- Input `1` → Output `1`
- Input `23` → Output `23` (internally converted to/from chrX)

## Reporting Feature

getSNPrs automatically generates comprehensive reports that include:

### Report Contents

1. **Summary Statistics**
   - Total SNPs queried
   - SNPs found vs not found
   - Success rate percentage

2. **Detailed Results**
   - Status of each SNP (FOUND/NOT_FOUND)
   - Chromosome and position information

3. **Warnings Section**
   - List of missing SNPs
   - Possible reasons for missing data

4. **Tool Information**
   - Processing parameters used
   - Timestamp and version info

### Example Report

```
# getSNPrs Analysis Report
# Generated on: Sun Jun 22 14:30:15 2025
# Input file: my_snps.txt
# Reference: 1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz

## Summary Statistics
Total SNPs queried: 100
SNPs found: 87
SNPs not found: 13
Success rate: 87%

## Detailed Results
# Status	Chromosome	Position
FOUND	chr1	998371
FOUND	chr1	998395
NOT_FOUND	chr2	123456789
...

## Warnings
⚠️  13 SNPs were not found in the reference dataset.

Possible reasons for missing SNPs:
- SNP position does not exist in the reference
- Different genome build (currently using hg19)
- Chromosome naming mismatch
- Position outside of covered regions

## Missing SNPs
# Chromosome	Position
chr2	123456789
chr3	999999999
...
```

### Report Control

- **Auto-generated**: By default, reports use input filename + "_getSNPrs_report.txt"
- **Custom name**: Use `--report filename.txt` to specify
- **Disable**: Use `--no-report` to skip report generation

### Default Reference (hg19)

By default, the tool uses the 1000 Genomes Phase 1 high-confidence SNPs:
- **VCF**: `1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz`
- **Index**: `1000G_phase1.snps.high_confidence.hg19.sites.vcf.idx.gz`

These files are automatically downloaded from:
```
ftp://gsapubftp-anonymous@ftp.broadinstitute.org/bundle/hg19/1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz
ftp://gsapubftp-anonymous@ftp.broadinstitute.org/bundle/hg19/1000G_phase1.snps.high_confidence.hg19.sites.vcf.idx.gz
```

### Using Custom Reference Files

You can provide your own VCF reference file:

```bash
./getSNPrs.sh -i my_snps.txt -r /path/to/my_reference.vcf.gz
```

**Requirements for custom VCF files:**
- Must be bgzip-compressed (`.vcf.gz`)
- Must have a corresponding index file:
  - **Preferred**: `.vcf.gz.csi` (bcftools) or `.vcf.gz.tbi` (tabix)
  - **Legacy**: `.vcf.gz.idx.gz` (GATK-style, will be converted automatically)
- Should use standard chromosome naming (chr1, chr2, ..., chrX, chrY, chrMT)

### Index File Formats

getSNPrs supports multiple VCF index formats:

1. **CSI format** (`.csi`): Created by `bcftools index`
2. **TBI format** (`.tbi`): Created by `tabix -p vcf`  
3. **GATK format** (`.idx.gz`): Legacy format, automatically converted

If you have a `.idx.gz` file (like the default reference), the tool will automatically attempt to create a bcftools-compatible index for better performance.

## Performance

### Benchmarks

Typical performance on a modern system (8 cores, SSD):

| Dataset Size | Processing Mode | Time | Throughput |
|--------------|----------------|------|------------|
| 100 SNPs | Direct | ~2 seconds | 50 SNPs/sec |
| 1,000 SNPs | Direct | ~15 seconds | 67 SNPs/sec |
| 10,000 SNPs | Parallel (4 threads) | ~45 seconds | 222 SNPs/sec |
| 100,000 SNPs | Parallel (8 threads) | ~6 minutes | 278 SNPs/sec |

### Performance Tips

1. **Use more threads** for large datasets:
   ```bash
   ./getSNPrs.sh -i large_file.txt -t 8
   ```

2. **Adjust chunk size** based on your system:
   ```bash
   # Larger chunks for more memory, fewer overhead
   ./getSNPrs.sh -i file.txt -s 5000
   
   # Smaller chunks for less memory usage
   ./getSNPrs.sh -i file.txt -s 500
   ```

3. **Use local reference files** to avoid download time:
   ```bash
   ./getSNPrs.sh -i file.txt -r local_reference.vcf.gz
   ```

4. **Use SSD storage** for better I/O performance

## Chromosome Handling

The tool intelligently handles different chromosome naming conventions:

### Input → Internal → Output Conversion

| Input Format | Internal Format | Output Format |
|-------------|----------------|---------------|
| chr1 | chr1 | chr1 |
| 1 | chr1 | 1 |
| chr23 | chrX | chr23 |
| 23 | chrX | 23 |
| chrX | chrX | chrX |
| X | chrX | X |
| chr24 | chrY | chr24 |
| 24 | chrY | 24 |
| chrY | chrY | chrY |
| Y | chrY | Y |
| chr25 | chrMT | chr25 |
| 25 | chrMT | 25 |
| chrMT | chrMT | chrMT |
| MT | chrMT | MT |

## Error Handling

The tool includes comprehensive error checking:

- **Missing dependencies**: Checks for required tools
- **File validation**: Verifies input and reference files exist
- **Format validation**: Ensures proper chromosome and position formats
- **Memory management**: Handles large files without memory exhaustion
- **Network issues**: Graceful handling of download failures

## Troubleshooting

### Common Issues

1. **"bcftools not found"**
   ```bash
   # Install bcftools (see installation section)
   sudo apt-get install bcftools  # Ubuntu/Debian
   ```

2. **"Permission denied"**
   ```bash
   chmod +x getSNPrs.sh
   ```

3. **"syntax error in expression" or arithmetic errors**
   ```bash
   # This usually indicates input file format issues
   # Ensure your input file has proper chromosome and position format
   # Check for empty lines or non-numeric positions
   ```

4. **"Failed to create VCF index" or slow performance**
   ```bash
   # Install tabix for better indexing support
   sudo apt-get install tabix  # Ubuntu/Debian
   
   # Or manually create an index
   bcftools index your_file.vcf.gz
   # OR
   tabix -p vcf your_file.vcf.gz
   
   # The tool will still work without an index, just slower
   ```

5. **"Reference file download failed"**
   ```bash
   # Check internet connection or use local reference
   ./getSNPrs.sh -i file.txt -r local_reference.vcf.gz
   ```

6. **"No results found"**
   - Check chromosome format consistency
   - Verify position coordinates are correct
   - Ensure reference file covers your regions of interest
   - Try with debug output to see what's happening

7. **Memory issues with large files**
   ```bash
   # Reduce chunk size
   ./getSNPrs.sh -i large_file.txt -s 100
   ```

### VCF File Requirements

For optimal performance, VCF files should be:
- **Compressed**: Use bgzip compression (`.vcf.gz`)
- **Indexed**: Have a corresponding index file (`.csi` or `.tbi`)
- **Properly formatted**: Follow VCF specification

The tool will automatically attempt to create an index if missing, but this may fail due to permissions or tool availability.

### Debug Mode

For debugging, you can run with verbose output:
```bash
bash -x ./getSNPrs.sh -i file.txt
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Citation

If you use getSNPrs in your research, please cite:

```
getSNPrs: A fast parallel SNP lookup tool for genomic analysis
```

## Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review the examples for proper usage

## Changelog

### Version 1.0
- Initial release
- Support for hg19 reference
- Parallel processing capabilities
- Flexible chromosome format handling
- Automatic delimiter detection