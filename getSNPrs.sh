#!/bin/bash

# getSNPrs - A fast SNP lookup tool
# Author: getSNPrs
# Version: 1.0
# Description: Search for SNPs in reference VCF files based on chromosome and position

set -euo pipefail

# Default parameters
THREADS=4
OUTPUT_FILE=""
REFERENCE_VCF=""
BUILD="hg19"
DELIMITER="auto"
OUTPUT_DELIMITER="auto"
QUIET=false
SPLIT_SIZE=1000
INFO_FIELDS=""
REPORT_FILE=""
GENERATE_REPORT=true

# URLs for reference files
HG19_VCF_URL="ftp://gsapubftp-anonymous@ftp.broadinstitute.org/bundle/hg19/1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz"
HG19_IDX_URL="ftp://gsapubftp-anonymous@ftp.broadinstitute.org/bundle/hg19/1000G_phase1.snps.high_confidence.hg19.sites.vcf.idx.gz"

# Default reference files
DEFAULT_VCF="1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz"
DEFAULT_IDX="1000G_phase1.snps.high_confidence.hg19.sites.vcf.idx.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

print_warning() {
    if [ "$QUIET" = false ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    fi
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    fi
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] -i INPUT_FILE

A fast SNP lookup tool that searches for SNPs in reference VCF files.

OPTIONS:
    -i, --input FILE        Input file with chromosome and position (required)
    -o, --output FILE       Output file (default: stdout)
    -r, --reference FILE    Reference VCF file (default: auto-download)
    -t, --threads NUM       Number of threads for parallel processing (default: 4)
    -b, --build BUILD       Genome build (default: hg19, only hg19 supported)
    -d, --delimiter CHAR    Input delimiter: 'tab', 'space', or 'auto' (default: auto)
    -D, --output-delimiter CHAR Output delimiter: 'tab', 'space', or 'auto' (default: auto)
    -s, --split-size NUM    Number of SNPs per chunk for parallel processing (default: 1000)
    -I, --info FIELDS      Additional INFO fields to include (comma-separated, e.g., "AC,AF,DP")
    -R, --report FILE       Generate report file (default: auto-generated name)
    --no-report             Disable report generation
    -q, --quiet             Suppress informational messages
    -h, --help              Show this help message

INPUT FORMAT:
    The input file should contain chromosome and position separated by space or tab:
    
    Examples:
        chr1 998371
        chr2 954
        
    Or numeric format:
        1 998371
        2 954
        
    Special chromosomes:
        X, Y, MT are supported
        If provided as 23, 24, 25 they will be converted to X, Y, MT

OUTPUT FORMAT:
    Default output: CHROM POS ID REF ALT
    With INFO fields: CHROM POS ID REF ALT [INFO_FIELDS]
    
    Missing SNPs will have "." for missing fields (ID, REF, ALT, INFO)
    The chromosome format in output will match the input format.

EXAMPLES:
    # Basic usage with default fields
    $0 -i snps.txt
    
    # Include additional INFO fields
    $0 -i snps.txt --info "AC,AF,DP"
    
    # With custom output file and 8 threads
    $0 -i snps.txt -o results.txt -t 8
    
    # With report file
    $0 -i snps.txt -o results.txt --report snp_report.txt
    
    # Disable report generation
    $0 -i snps.txt --no-report

EOF
}

# Function to check dependencies
check_dependencies() {
    local deps=("bcftools" "wget" "gunzip" "sort" "uniq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_error "Please install the missing tools and try again."
        exit 1
    fi
}

# Function to detect delimiter
detect_delimiter() {
    local file="$1"
    local tab_count=$(head -n 10 "$file" | grep -o $'\t' | wc -l)
    local space_count=$(head -n 10 "$file" | grep -o ' ' | wc -l)
    
    if [ "$tab_count" -gt "$space_count" ]; then
        echo "tab"
    else
        echo "space"
    fi
}

# Function to normalize chromosome format
normalize_chromosome() {
    local chr="$1"
    local input_format="$2"
    
    # Remove chr prefix for processing
    local norm_chr="${chr#chr}"
    
    # Convert numeric sex chromosomes
    case "$norm_chr" in
        23) norm_chr="X" ;;
        24) norm_chr="Y" ;;
        25) norm_chr="MT" ;;
    esac
    
    # Return in reference format (always with chr prefix for hg19)
    echo "chr${norm_chr}"
}

# Function to format output chromosome
format_output_chromosome() {
    local ref_chr="$1"
    local original_chr="$2"
    
    # If original had chr prefix, keep it
    if [[ "$original_chr" =~ ^chr ]]; then
        echo "$ref_chr"
    else
        # Remove chr prefix for numeric format
        local num_chr="${ref_chr#chr}"
        # Convert back sex chromosomes if needed
        case "$num_chr" in
            X) if [[ "$original_chr" == "23" ]]; then echo "23"; else echo "X"; fi ;;
            Y) if [[ "$original_chr" == "24" ]]; then echo "24"; else echo "Y"; fi ;;
            MT) if [[ "$original_chr" == "25" ]]; then echo "25"; else echo "MT"; fi ;;
            *) echo "$num_chr" ;;
        esac
    fi
}

# Function to download reference files
download_reference() {
    local vcf_file="$1"
    local idx_file="$2"
    
    print_info "Downloading reference VCF file..."
    if ! wget -q --show-progress "$HG19_VCF_URL" -O "$vcf_file"; then
        print_error "Failed to download VCF file"
        exit 1
    fi
    
    print_info "Downloading reference index file..."
    if ! wget -q --show-progress "$HG19_IDX_URL" -O "$idx_file"; then
        print_error "Failed to download index file"
        exit 1
    fi
    
    print_success "Reference files downloaded successfully"
}

# Function to search SNPs in a chunk
search_snp_chunk() {
    local chunk_file="$1"
    local reference_vcf="$2"
    local input_delim="$3"
    local output_delim="$4"
    local temp_output="$5"
    local info_fields="$6"
    local temp_report="$7"
    
    local real_input_delim real_output_delim
    
    # Set actual delimiters
    if [ "$input_delim" = "tab" ]; then
        real_input_delim=$'\t'
    else
        real_input_delim=' '
    fi
    
    if [ "$output_delim" = "tab" ]; then
        real_output_delim=$'\t'
    else
        real_output_delim=' '
    fi
    
    # Build format string for bcftools
    local format_string='%CHROM\t%POS\t%ID\t%REF\t%ALT'
    local info_array=()
    if [ -n "$info_fields" ]; then
        IFS=',' read -ra info_array <<< "$info_fields"
        for field in "${info_array[@]}"; do
            format_string="${format_string}\t%INFO/${field}"
        done
    fi
    format_string="${format_string}\n"
    
    # Process each line in the chunk
    while IFS="$real_input_delim" read -r chr pos rest; do
        # Skip empty lines and comments
        [[ -z "$chr" || "$chr" =~ ^# ]] && continue
        
        # Validate position is numeric
        if ! [[ "$pos" =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        # Normalize chromosome for reference lookup
        local ref_chr=$(normalize_chromosome "$chr" "input")
        
        # Search in VCF using bcftools
        local result=$(bcftools query -r "${ref_chr}:${pos}-${pos}" -f "$format_string" "$reference_vcf" 2>/dev/null)
        
        # Format output chromosome to match input format
        local output_chr=$(format_output_chromosome "$ref_chr" "$chr")
        
        if [ -n "$result" ]; then
            # SNP found - replace chromosome in result and adjust delimiter
            local formatted_result
            if [ "$output_delim" = "space" ]; then
                formatted_result=$(echo "$result" | sed "s/^$ref_chr/$output_chr/" | tr '\t' ' ')
            else
                formatted_result=$(echo "$result" | sed "s/^$ref_chr/$output_chr/")
            fi
            echo "$formatted_result" >> "$temp_output"
            
            # Add to report (found)
            if [ -n "$temp_report" ]; then
                echo "FOUND${real_output_delim}${output_chr}${real_output_delim}${pos}" >> "$temp_report"
            fi
        else
            # SNP not found - create line with missing data
            local missing_line="${output_chr}${real_output_delim}${pos}${real_output_delim}.${real_output_delim}.${real_output_delim}."
            
            # Add missing INFO fields if requested
            if [ -n "$info_fields" ]; then
                for field in "${info_array[@]}"; do
                    missing_line="${missing_line}${real_output_delim}."
                done
            fi
            
            echo "$missing_line" >> "$temp_output"
            
            # Add to report (not found)
            if [ -n "$temp_report" ]; then
                echo "NOT_FOUND${real_output_delim}${output_chr}${real_output_delim}${pos}" >> "$temp_report"
            fi
        fi
    done < "$chunk_file"
}

# Function to generate summary report
generate_report() {
    local input_file="$1"
    local report_data="$2"
    local report_file="$3"
    local output_delim="$4"
    
    # Count statistics
    local total_snps=$(wc -l < "$input_file")
    local found_snps=0
    local not_found_snps=0
    
    if [ -f "$report_data" ]; then
        found_snps=$(grep -c "^FOUND" "$report_data" 2>/dev/null || echo "0")
        not_found_snps=$(grep -c "^NOT_FOUND" "$report_data" 2>/dev/null || echo "0")
    fi
    
    # Set delimiter for report
    local delim
    if [ "$output_delim" = "tab" ]; then
        delim=$'\t'
    else
        delim=' '
    fi
    
    # Generate report
    cat > "$report_file" << EOF
# getSNPrs Analysis Report
# Generated on: $(date)
# Input file: $input_file
# Reference: $REFERENCE_VCF

## Summary Statistics
Total SNPs queried: $total_snps
SNPs found: $found_snps
SNPs not found: $not_found_snps
Success rate: $(( found_snps * 100 / total_snps ))%

## Detailed Results
# Status${delim}Chromosome${delim}Position
EOF
    
    # Add detailed results if available
    if [ -f "$report_data" ]; then
        cat "$report_data" >> "$report_file"
    fi
    
    # Add warnings section
    if [ "$not_found_snps" -gt 0 ]; then
        cat >> "$report_file" << EOF

## Warnings
⚠️  $not_found_snps SNPs were not found in the reference dataset.

Possible reasons for missing SNPs:
- SNP position does not exist in the reference
- Different genome build (currently using $BUILD)
- Chromosome naming mismatch
- Position outside of covered regions

## Missing SNPs
EOF
        if [ -f "$report_data" ]; then
            echo "# Chromosome${delim}Position" >> "$report_file"
            grep "^NOT_FOUND" "$report_data" | cut -d"$delim" -f2,3 >> "$report_file"
        fi
    fi
    
    # Add footer
    cat >> "$report_file" << EOF

## Tool Information
getSNPrs version: 1.0
Processing completed: $(date)
Threads used: $THREADS
EOF
}

# Function to process SNPs with parallel processing
process_snps() {
    local input_file="$1"
    local reference_vcf="$2"
    local output_file="$3"
    local input_delim="$4"
    local output_delim="$5"
    local info_fields="$6"
    local report_file="$7"
    
    # Count total lines
    local total_lines=$(wc -l < "$input_file")
    print_info "Processing $total_lines SNPs..."
    
    # Create temporary report data file if report generation is enabled
    local temp_report_data=""
    if [ "$GENERATE_REPORT" = true ]; then
        temp_report_data=$(mktemp)
    fi
    
    # If file is small, process directly
    if [ "$total_lines" -le "$SPLIT_SIZE" ]; then
        print_info "Processing file directly (small size)"
        if [ -n "$output_file" ]; then
            search_snp_chunk "$input_file" "$reference_vcf" "$input_delim" "$output_delim" "$output_file" "$info_fields" "$temp_report_data"
        else
            search_snp_chunk "$input_file" "$reference_vcf" "$input_delim" "$output_delim" "/dev/stdout" "$info_fields" "$temp_report_data"
        fi
    else
        # Create temporary directory for chunks
        local temp_dir=$(mktemp -d)
        local temp_prefix="$temp_dir/chunk_"
        
        print_info "Splitting file into chunks for parallel processing..."
        
        # Split input file into chunks
        split -l "$SPLIT_SIZE" -d "$input_file" "$temp_prefix"
        
        # Get list of chunk files
        local chunk_files=("$temp_dir"/chunk_*)
        local num_chunks=${#chunk_files[@]}
        
        print_info "Created $num_chunks chunks, processing with $THREADS threads..."
        
        # Process chunks in parallel
        local pids=()
        local temp_outputs=()
        local temp_reports=()
        
        for chunk_file in "${chunk_files[@]}"; do
            # Wait if we've reached the thread limit
            while [ ${#pids[@]} -ge "$THREADS" ]; do
                for i in "${!pids[@]}"; do
                    if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                        unset "pids[$i]"
                    fi
                done
                pids=("${pids[@]}")  # Reindex array
                sleep 0.1
            done
            
            # Create temporary output file for this chunk
            local temp_output=$(mktemp)
            temp_outputs+=("$temp_output")
            
            # Create temporary report file for this chunk if needed
            local temp_report=""
            if [ "$GENERATE_REPORT" = true ]; then
                temp_report=$(mktemp)
                temp_reports+=("$temp_report")
            fi
            
            # Start processing this chunk in background
            search_snp_chunk "$chunk_file" "$reference_vcf" "$input_delim" "$output_delim" "$temp_output" "$info_fields" "$temp_report" &
            pids+=($!)
        done
        
        # Wait for all background jobs to complete
        print_info "Waiting for all chunks to complete..."
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        # Combine results
        print_info "Combining results..."
        if [ -n "$output_file" ]; then
            cat "${temp_outputs[@]}" > "$output_file" 2>/dev/null || true
        else
            cat "${temp_outputs[@]}" 2>/dev/null || true
        fi
        
        # Combine report data
        if [ "$GENERATE_REPORT" = true ] && [ ${#temp_reports[@]} -gt 0 ]; then
            cat "${temp_reports[@]}" > "$temp_report_data" 2>/dev/null || true
            rm -f "${temp_reports[@]}"
        fi
        
        # Cleanup
        rm -rf "$temp_dir"
        rm -f "${temp_outputs[@]}"
    fi
    
    # Generate report if enabled
    if [ "$GENERATE_REPORT" = true ] && [ -n "$report_file" ]; then
        print_info "Generating report..."
        generate_report "$input_file" "$temp_report_data" "$report_file" "$output_delim"
        print_success "Report generated: $report_file"
    fi
    
    # Cleanup temporary report data
    if [ -n "$temp_report_data" ]; then
        rm -f "$temp_report_data"
    fi
    
    print_success "Processing completed"
}

# Main function
main() {
    local input_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -r|--reference)
                REFERENCE_VCF="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            -b|--build)
                BUILD="$2"
                shift 2
                ;;
            -d|--delimiter)
                DELIMITER="$2"
                shift 2
                ;;
            -D|--output-delimiter)
                OUTPUT_DELIMITER="$2"
                shift 2
                ;;
            -s|--split-size)
                SPLIT_SIZE="$2"
                shift 2
                ;;
            -I|--info)
                INFO_FIELDS="$2"
                shift 2
                ;;
            -R|--report)
                REPORT_FILE="$2"
                shift 2
                ;;
            --no-report)
                GENERATE_REPORT=false
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$input_file" ]; then
        print_error "Input file is required"
        usage
        exit 1
    fi
    
    if [ ! -f "$input_file" ]; then
        print_error "Input file does not exist: $input_file"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Validate build
    if [ "$BUILD" != "hg19" ]; then
        print_error "Only hg19 build is currently supported"
        exit 1
    fi
    
    # Set reference VCF file
    if [ -z "$REFERENCE_VCF" ]; then
        REFERENCE_VCF="$DEFAULT_VCF"
        
        # Download reference files if they don't exist
        if [ ! -f "$REFERENCE_VCF" ] || [ ! -f "$DEFAULT_IDX" ]; then
            download_reference "$REFERENCE_VCF" "$DEFAULT_IDX"
        fi
    fi
    
    if [ ! -f "$REFERENCE_VCF" ]; then
        print_error "Reference VCF file does not exist: $REFERENCE_VCF"
        exit 1
    fi
    
    # Auto-detect delimiters if needed
    if [ "$DELIMITER" = "auto" ]; then
        DELIMITER=$(detect_delimiter "$input_file")
        print_info "Auto-detected input delimiter: $DELIMITER"
    fi
    
    if [ "$OUTPUT_DELIMITER" = "auto" ]; then
        OUTPUT_DELIMITER="$DELIMITER"
        print_info "Using output delimiter: $OUTPUT_DELIMITER"
    fi
    
    # Validate delimiter values
    if [[ "$DELIMITER" != "tab" && "$DELIMITER" != "space" ]]; then
        print_error "Invalid input delimiter. Use 'tab' or 'space'"
        exit 1
    fi
    
    if [[ "$OUTPUT_DELIMITER" != "tab" && "$OUTPUT_DELIMITER" != "space" ]]; then
        print_error "Invalid output delimiter. Use 'tab' or 'space'"
        exit 1
    fi
    
    # Validate thread count
    if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [ "$THREADS" -lt 1 ]; then
        print_error "Thread count must be a positive integer"
        exit 1
    fi
    
    # Validate split size
    if ! [[ "$SPLIT_SIZE" =~ ^[0-9]+$ ]] || [ "$SPLIT_SIZE" -lt 1 ]; then
        print_error "Split size must be a positive integer"
        exit 1
    fi
    
    # Validate INFO fields format
    if [ -n "$INFO_FIELDS" ]; then
        if [[ ! "$INFO_FIELDS" =~ ^[A-Za-z0-9_,]+$ ]]; then
            print_error "INFO fields must be comma-separated alphanumeric field names"
            exit 1
        fi
    fi
    
    # Set default report file if not specified and reports are enabled
    if [ "$GENERATE_REPORT" = true ] && [ -z "$REPORT_FILE" ]; then
        local base_name=$(basename "$input_file" .txt)
        REPORT_FILE="${base_name}_getSNPrs_report.txt"
        print_info "Report will be saved to: $REPORT_FILE"
    fi
    
    print_info "Starting getSNPrs with the following parameters:"
    print_info "  Input file: $input_file"
    print_info "  Output: ${OUTPUT_FILE:-stdout}"
    print_info "  Reference: $REFERENCE_VCF"
    print_info "  Threads: $THREADS"
    print_info "  Input delimiter: $DELIMITER"
    print_info "  Output delimiter: $OUTPUT_DELIMITER"
    print_info "  Split size: $SPLIT_SIZE"
    print_info "  INFO fields: ${INFO_FIELDS:-none}"
    print_info "  Report file: ${REPORT_FILE:-none}"
    print_info "  Generate report: $GENERATE_REPORT"
    
    # Process SNPs
    process_snps "$input_file" "$REFERENCE_VCF" "$OUTPUT_FILE" "$DELIMITER" "$OUTPUT_DELIMITER" "$INFO_FIELDS" "$REPORT_FILE"
}

# Run main function with all arguments
main "$@"
