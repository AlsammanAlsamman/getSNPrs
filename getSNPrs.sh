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

# Default reference files  
DEFAULT_VCF="1000G_phase1.snps.high_confidence.hg19.sites.vcf.gz"

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
    Default output always includes: CHROM POS ID REF ALT
    - CHROM: Chromosome name
    - POS: Position
    - ID: SNP identifier (rs number if available, "." if missing)
    - REF: Reference allele
    - ALT: Alternative allele
    
    With additional INFO fields: CHROM POS ID REF ALT [INFO_FIELDS]
    
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
    local deps=("bcftools" "wget" "gunzip" "sort" "uniq" "bgzip")
    local optional_deps=("tabix" "zcat")
    local missing=()
    local missing_optional=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_optional+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        print_error "Please install the missing tools and try again."
        exit 1
    fi
    
    if [ ${#missing_optional[@]} -ne 0 ]; then
        print_warning "Missing optional dependencies: ${missing_optional[*]}"
        print_warning "Some features may not work optimally."
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

# Function to detect VCF chromosome naming convention
detect_vcf_chromosome_format() {
    local vcf_file="$1"
    
    # Check if VCF uses chr prefix by looking at the actual data rows, not headers
    local first_chr=$(bcftools view -H "$vcf_file" | head -n 1 | cut -f1 2>/dev/null || echo "")
    
    # Also test with a direct query to be sure
    if bcftools query -r "chr1:1000000-1000000" -f "%CHROM\n" "$vcf_file" 2>/dev/null | head -n 1 | grep -q "chr"; then
        echo "chr_prefix"
    elif bcftools query -r "1:1000000-1000000" -f "%CHROM\n" "$vcf_file" 2>/dev/null | head -n 1 | grep -q "^[0-9XYM]"; then
        echo "no_prefix"
    elif [[ "$first_chr" =~ ^chr ]]; then
        echo "chr_prefix"
    else
        echo "no_prefix"
    fi
}

# Global variable to store VCF chromosome format
VCF_CHR_FORMAT=""

# Function to normalize chromosome format
normalize_chromosome() {
    local chr="$1"

    # Remove chr prefix first to handle both '1' and 'chr1' inputs consistently
    local norm_chr="${chr#chr}"

    # Convert numeric sex chromosomes
    case "$norm_chr" in
        23) norm_chr="X" ;;
        24) norm_chr="Y" ;;
        25) norm_chr="MT" ;;
    esac

    # Return in reference format based on VCF naming convention
    if [ "$VCF_CHR_FORMAT" = "chr_prefix" ]; then
        echo "chr${norm_chr}"
    else
        echo "${norm_chr}"
    fi
}

# Function to format output chromosome
format_output_chromosome() {
    local ref_chr="$1"
    local original_chr="$2"

    # If original had chr prefix, keep it
    if [[ "$original_chr" =~ ^chr ]]; then
        echo "$ref_chr"
    else
        # Remove chr prefix for numeric output format
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

# Function to ensure VCF file is indexed
ensure_vcf_indexed() {
    local vcf_file="$1"
    
    # Check if bcftools-compatible index exists
    if [ -f "${vcf_file}.csi" ] || [ -f "${vcf_file}.tbi" ]; then
        return 0
    fi
    
    print_info "VCF file is not indexed. Creating index for optimal performance..."
    
    # Check if file is bgzip compressed
    if ! file "$vcf_file" | grep -q "gzip compressed"; then
        print_info "VCF file is not bgzip compressed. Compressing..."
        if [ "${vcf_file##*.}" = "gz" ]; then
            # File has .gz extension but is not properly compressed
            local temp_file="${vcf_file%.gz}"
            gunzip -c "$vcf_file" > "$temp_file"
            bgzip "$temp_file"
        else
            # File is uncompressed
            bgzip "$vcf_file"
            vcf_file="${vcf_file}.gz"
        fi
    fi
    
    # Try to create index
    if bcftools index "$vcf_file" 2>/dev/null; then
        print_success "Created CSI index successfully"
        return 0
    elif command -v tabix >/dev/null 2>&1 && tabix -p vcf "$vcf_file" 2>/dev/null; then
        print_success "Created TBI index successfully"
        return 0
    else
        print_warning "Failed to create VCF index."
        print_warning "This will cause slower performance but the tool will still work."
        print_warning "To improve performance, manually create an index with:"
        print_warning "  bcftools index $vcf_file"
        return 1
    fi
}

# Function to download reference files
download_reference() {
    local vcf_file="$1"
    
    print_info "Downloading reference VCF file to current directory..."
    if ! wget -q --show-progress "$HG19_VCF_URL" -O "$vcf_file.tmp"; then
        print_error "Failed to download VCF file"
        exit 1
    fi
    
    print_success "Reference VCF file downloaded successfully"
    
    # Check if file is properly bgzip compressed
    print_info "Preparing VCF file for indexing..."
    
    # Decompress, then recompress with bgzip to ensure compatibility
    print_info "Decompressing VCF file..."
    if ! gunzip -c "$vcf_file.tmp" > "${vcf_file%.gz}"; then
        print_error "Failed to decompress VCF file"
        rm -f "$vcf_file.tmp"
        exit 1
    fi
    
    print_info "Recompressing with bgzip for optimal indexing..."
    if ! bgzip "${vcf_file%.gz}"; then
        print_error "Failed to recompress VCF file with bgzip"
        rm -f "$vcf_file.tmp" "${vcf_file%.gz}"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f "$vcf_file.tmp"
    
    print_info "Creating bcftools index..."
    if bcftools index "$vcf_file" 2>/dev/null; then
        print_success "Created bcftools CSI index: ${vcf_file}.csi"
    elif command -v tabix >/dev/null 2>&1 && tabix -p vcf "$vcf_file" 2>/dev/null; then
        print_success "Created tabix TBI index: ${vcf_file}.tbi"
    else
        print_error "Failed to create index file"
        exit 1
    fi
    
    print_success "Reference file is ready: $vcf_file"
}

# Function to search SNPs in a chunk using efficient batch processing
search_snp_chunk() {
    local chunk_file="$1"
    local reference_vcf="$2"
    local input_delim="$3"
    local output_delim="$4"
    local temp_output="$5"
    local info_fields="$6"
    local temp_report="$7"

    local real_input_delim=$'\t'
    [ "$input_delim" = "space" ] && real_input_delim=' '
    local real_output_delim=$'\t'
    [ "$output_delim" = "space" ] && real_output_delim=' '

    # Default output format always includes: CHROM POS ID REF ALT
    local format_string='%CHROM\t%POS\t%ID\t%REF\t%ALT'
    if [ -n "$info_fields" ]; then
        local info_array
        IFS=',' read -ra info_array <<< "$info_fields"
        for field in "${info_array[@]}"; do
            format_string="${format_string}\t%INFO/${field}"
        done
    fi
    format_string="${format_string}\n"

    local temp_regions=$(mktemp)
    local temp_input_map=$(mktemp)
    local temp_input_order=$(mktemp)
    local line_count=0
    local processed_count=0

    # Create associative array for input order tracking
    declare -A input_order_map
    local order_counter=0

    # Robust input parsing loop
    while IFS="$real_input_delim" read -r chr pos rest; do
        line_count=$((line_count + 1))
        
        # Trim whitespace and handle Windows line endings
        chr=$(echo "$chr" | tr -d '[:space:]' | tr -d '\r')
        pos=$(echo "$pos" | tr -d '[:space:]' | tr -d '\r')

        # Skip empty, commented, or invalid lines
        if [[ -z "$chr" || -z "$pos" || "$chr" =~ ^# || ! "$pos" =~ ^[0-9]+$ ]]; then
            continue
        fi

        processed_count=$((processed_count + 1))
        order_counter=$((order_counter + 1))
        
        local ref_chr=$(normalize_chromosome "$chr")
        
        # Write regions file entry - use tab-separated format for bcftools -R
        echo -e "${ref_chr}\t${pos}" >> "$temp_regions"
        
        # Store mapping: ref_chr:pos -> original_chr,order
        echo -e "${ref_chr}:${pos}\t${chr}\t${order_counter}" >> "$temp_input_map"
        
        # Store input order: order -> chr,pos
        echo -e "${order_counter}\t${chr}\t${pos}" >> "$temp_input_order"
        
        # Store in associative array for fast lookup
        input_order_map["${ref_chr}:${pos}"]="${chr}\t${pos}\t${order_counter}"
    done < "$chunk_file"

    local temp_results=$(mktemp)
    local bcftools_success=0
    
    if [ $processed_count -gt 0 ] && [ -s "$temp_regions" ]; then
        # Clean and validate regions file - use tab-separated format
        sort -u "$temp_regions" | awk 'NF == 2 && $1 ~ /^[^[:space:]]+$/ && $2 ~ /^[0-9]+$/' > "${temp_regions}.clean"
        
        # Debug: check if regions file is properly formatted
        if [ ! -s "${temp_regions}.clean" ]; then
            print_warning "No valid regions found in regions file for chunk $chunk_file"
        else
            # Debug: show first few regions and VCF header
            print_info "Sample regions: $(head -n 3 "${temp_regions}.clean" | tr '\n' ' ' | tr '\t' ':')"
            print_info "VCF chromosomes: $(bcftools view -h "$reference_vcf" | grep "^##contig" | head -n 3 | cut -d'=' -f3 | cut -d',' -f1 | tr '\n' ' ')"
            print_info "First data chromosome: $(bcftools view -H "$reference_vcf" | head -n 1 | cut -f1 2>/dev/null || echo 'N/A')"
            
            # Query bcftools with cleaned regions file
            if bcftools query -R "${temp_regions}.clean" -f "$format_string" "$reference_vcf" > "$temp_results" 2>/dev/null; then
                bcftools_success=1
                print_info "bcftools query succeeded, found $(wc -l < "$temp_results") results"
            else
                print_warning "bcftools query failed for chunk $chunk_file. Check VCF file and chromosome naming."
                # Try test queries with both naming conventions
                print_info "Testing VCF file with different chromosome formats..."
                
                # Test with chr prefix
                local test_chr_result=$(bcftools query -r "chr1:1000000-1000000" -f "%CHROM\t%POS\n" "$reference_vcf" 2>/dev/null | head -n 1)
                if [ -n "$test_chr_result" ]; then
                    print_info "VCF responds to 'chr1' queries: $test_chr_result"
                fi
                
                # Test without chr prefix
                local test_num_result=$(bcftools query -r "1:1000000-1000000" -f "%CHROM\t%POS\n" "$reference_vcf" 2>/dev/null | head -n 1)
                if [ -n "$test_num_result" ]; then
                    print_info "VCF responds to '1' queries: $test_num_result"
                fi
                
                # Test one of our actual regions with both formats
                local first_region_line=$(head -n 1 "${temp_regions}.clean")
                local first_chr=$(echo "$first_region_line" | cut -f1)
                local first_pos=$(echo "$first_region_line" | cut -f2)
                local first_region="${first_chr}:${first_pos}-${first_pos}"
                local numeric_chr=$(echo "$first_chr" | sed 's/chr//')
                local numeric_region="${numeric_chr}:${first_pos}-${first_pos}"
                print_info "Testing our region '$first_region' vs '$numeric_region'"
                
                local our_chr_test=$(bcftools query -r "$first_region" -f "%CHROM\t%POS\n" "$reference_vcf" 2>/dev/null | head -n 1)
                local our_num_test=$(bcftools query -r "$numeric_region" -f "%CHROM\t%POS\n" "$reference_vcf" 2>/dev/null | head -n 1)
                
                if [ -n "$our_chr_test" ]; then
                    print_info "Our chr-prefixed region works: $our_chr_test"
                    
                    # Since individual regions work, let's try a small regions file
                    print_info "Testing with a small regions file containing first 3 regions..."
                    local test_regions_file=$(mktemp)
                    head -n 3 "${temp_regions}.clean" > "$test_regions_file"
                    
                    print_info "Test regions file content (tab-separated chr pos):"
                    cat "$test_regions_file" | while read line; do print_info "  $line"; done
                    
                    local test_result=$(bcftools query -R "$test_regions_file" -f "%CHROM\t%POS\t%ID\n" "$reference_vcf" 2>&1)
                    if [ $? -eq 0 ] && [ -n "$test_result" ]; then
                        print_info "Small regions file query SUCCESS:"
                        echo "$test_result" | while read line; do print_info "  Found: $line"; done
                    else
                        print_warning "Small regions file query FAILED: $test_result"
                    fi
                    
                    rm -f "$test_regions_file"
                elif [ -n "$our_num_test" ]; then
                    print_info "Our numeric region works: $our_num_test"
                    print_warning "VCF uses numeric chromosomes but we're querying with chr prefix!"
                else
                    print_warning "Neither chromosome format works for our regions"
                fi
            fi
        fi
    fi

    # Create associative array for found SNPs
    declare -A found_snps
    local found_count=0
    
    if [ $bcftools_success -eq 1 ] && [ -s "$temp_results" ]; then
        # Parse bcftools results and build lookup map
        while IFS=$'\t' read -r ref_chr ref_pos snp_id ref_allele alt_allele rest_fields; do
            local key="${ref_chr}:${ref_pos}"
            local value="${snp_id}\t${ref_allele}\t${alt_allele}"
            if [ -n "$rest_fields" ]; then
                value="${value}\t${rest_fields}"
            fi
            found_snps["$key"]="$value"
            found_count=$((found_count + 1))
        done < "$temp_results"
    fi

    # Generate output in original input order
    local report_found=0
    local report_missing=0
    
    while IFS=$'\t' read -r order orig_chr orig_pos; do
        local ref_chr=$(normalize_chromosome "$orig_chr")
        local key="${ref_chr}:${orig_pos}"
        local output_chr=$(format_output_chromosome "$ref_chr" "$orig_chr")
        
        if [[ -n "${found_snps[$key]:-}" ]]; then
            # SNP found - output the result
            if [ "$real_output_delim" = $'\t' ]; then
                echo -e "${output_chr}\t${orig_pos}\t${found_snps[$key]}" >> "$temp_output"
            else
                echo "${output_chr} ${orig_pos} ${found_snps[$key]}" | tr '\t' ' ' >> "$temp_output"
            fi
            report_found=$((report_found + 1))
            
            # Add to report
            if [ "$GENERATE_REPORT" = true ] && [ -n "$temp_report" ]; then
                echo -e "FOUND\t${output_chr}\t${orig_pos}" >> "$temp_report"
            fi
        else
            # SNP not found - output with missing fields
            local missing_fields="."
            if [ -n "$info_fields" ]; then
                local info_array
                IFS=',' read -ra info_array <<< "$info_fields"
                for ((i=1; i<${#info_array[@]}; i++)); do
                    missing_fields="${missing_fields}\t."
                done
            fi
            
            if [ "$real_output_delim" = $'\t' ]; then
                echo -e "${output_chr}\t${orig_pos}\t.\t.\t.${missing_fields}" >> "$temp_output"
            else
                echo "${output_chr} ${orig_pos} . . .${missing_fields}" | tr '\t' ' ' >> "$temp_output"
            fi
            report_missing=$((report_missing + 1))
            
            # Add to report
            if [ "$GENERATE_REPORT" = true ] && [ -n "$temp_report" ]; then
                echo -e "NOT_FOUND\t${output_chr}\t${orig_pos}" >> "$temp_report"
            fi
        fi
    done < "$temp_input_order"

    # Clean up temporary files
    rm -f "$temp_regions" "${temp_regions}.clean" "$temp_input_map" "$temp_input_order" "$temp_results"
}

# Function to generate summary report
generate_report() {
    local input_file="$1"
    local report_data="$2"
    local report_file="$3"
    local output_delim="$4"
    
    # Count statistics
    local total_snps=0
    if [ -f "$input_file" ]; then
        total_snps=$(grep -c "^[^[:space:]]*[[:space:]]*[0-9]" "$input_file" 2>/dev/null)
        if [ -z "$total_snps" ] || ! [[ "$total_snps" =~ ^[0-9]+$ ]]; then
            total_snps=$(wc -l < "$input_file" 2>/dev/null || echo "0")
        fi
    fi
    
    local found_snps=0
    local not_found_snps=0
    
    if [ -f "$report_data" ] && [ -s "$report_data" ]; then
        found_snps=$(grep -c "^FOUND" "$report_data" 2>/dev/null)
        not_found_snps=$(grep -c "^NOT_FOUND" "$report_data" 2>/dev/null)
    fi
    
    # Ensure all variables are numeric and not empty
    total_snps=${total_snps:-0}
    found_snps=${found_snps:-0}
    not_found_snps=${not_found_snps:-0}
    
    # Validate that values are actually numbers
    if ! [[ "$total_snps" =~ ^[0-9]+$ ]]; then total_snps=0; fi
    if ! [[ "$found_snps" =~ ^[0-9]+$ ]]; then found_snps=0; fi
    if ! [[ "$not_found_snps" =~ ^[0-9]+$ ]]; then not_found_snps=0; fi
    
    # Calculate success rate safely
    local success_rate=0
    if [ "$total_snps" -gt 0 ] && [[ "$found_snps" =~ ^[0-9]+$ ]] && [[ "$total_snps" =~ ^[0-9]+$ ]]; then
        success_rate=$(( found_snps * 100 / total_snps ))
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
Success rate: ${success_rate}%

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
Reference used: $REFERENCE_VCF
Total SNPs: $total_snps, Found: $found_snps, Not found: $not_found_snps, Success rate: ${success_rate}%
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
    
    # Count total lines, excluding empty lines
    local total_lines=$(grep -c "^[^[:space:]]*[[:space:]]*[0-9]" "$input_file" 2>/dev/null || echo "0")
    if [ "$total_lines" -eq 0 ]; then
        total_lines=$(wc -l < "$input_file" 2>/dev/null || echo "0")
    fi
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
        if [ -n "$temp_report_data" ] && [ -f "$temp_report_data" ]; then
            generate_report "$input_file" "$temp_report_data" "$report_file" "$output_delim"
            print_success "Report generated: $report_file"
        else
            print_warning "No report data available, generating basic report"
            # Create empty temp file for basic report
            local empty_report=$(mktemp)
            generate_report "$input_file" "$empty_report" "$report_file" "$output_delim"
            rm -f "$empty_report"
            print_success "Basic report generated: $report_file"
        fi
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
        
        # Download reference file if it doesn't exist
        if [ ! -f "$REFERENCE_VCF" ]; then
            download_reference "$REFERENCE_VCF"
        fi
    fi
    
    if [ ! -f "$REFERENCE_VCF" ]; then
        print_error "Reference VCF file does not exist: $REFERENCE_VCF"
        exit 1
    fi
    
    # Ensure VCF file is indexed for optimal performance
    ensure_vcf_indexed "$REFERENCE_VCF"
    
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
    
    # Detect VCF chromosome naming convention
    print_info "Detecting VCF chromosome naming convention..."
    VCF_CHR_FORMAT=$(detect_vcf_chromosome_format "$REFERENCE_VCF")
    print_info "VCF uses chromosome format: $VCF_CHR_FORMAT"
    
    # Process SNPs
    process_snps "$input_file" "$REFERENCE_VCF" "$OUTPUT_FILE" "$DELIMITER" "$OUTPUT_DELIMITER" "$INFO_FIELDS" "$REPORT_FILE"
}

# Run main function with all arguments
main "$@"
