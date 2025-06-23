# getSNPrs Quick Start Guide

## 5-Minute Setup

### 1. Install Dependencies (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install bcftools wget
```

### 2. Make Scripts Executable
```bash
chmod +x getSNPrs.sh install.sh test_getSNPrs.sh
```

### 3. Quick Test
```bash
# Test with a simple SNP
echo "chr1 998371" | ./getSNPrs.sh -i /dev/stdin
```

## Common Usage Patterns

### Basic lookup from file (default: chr, pos, rsid, ref, alt)
```bash
./getSNPrs.sh -i my_snps.txt -o results.txt
```

### Add specific INFO fields (allele count, frequency, depth)
```bash
./getSNPrs.sh -i my_snps.txt --info "AC,AF,DP" -o results.txt
```

### Fast processing with more threads
```bash
./getSNPrs.sh -i large_file.txt -t 8 -o results.txt
```

### Generate detailed report
```bash
./getSNPrs.sh -i my_snps.txt -o results.txt --report detailed_analysis.txt
```

### Process from stdin (no report)
```bash
cat my_snps.txt | ./getSNPrs.sh -i /dev/stdin --no-report
```

## Input File Examples

### Chr-prefixed format
```
chr1    998371
chr2    12345
chrX    67890
```

### Numeric format
```
1       998371
2       12345
23      67890
```

## Expected Output

### Default Format (Essential Fields)
```
chr1    998371  .       A       G
chr1    998395  rs7526076       A       G
chr2    12345   .       .       .
```

### With INFO Fields
```
chr1    998371  .       A       G       6       0.0106
chr1    998395  rs7526076       A       G       1449    0.80679
chr2    12345   .       .       .       .       .
```

### Report Example
```
## Summary Statistics
Total SNPs queried: 3
SNPs found: 2
SNPs not found: 1
Success rate: 67%
```

## Troubleshooting

- **No bcftools**: Run `./install.sh`
- **No results**: Check chromosome format and coordinates
- **Permission denied**: Run `chmod +x getSNPrs.sh`
- **Large files slow**: Use `-t 8` for more threads
- **Too much output**: Use `--no-report` to disable reporting
- **Missing INFO fields**: Check field names are correct (e.g., "AC,AF,DP")

## Need Help?

- Run `./getSNPrs.sh --help` for all options
- Run `./test_getSNPrs.sh` for examples
- Check the full README.md for detailed documentation
