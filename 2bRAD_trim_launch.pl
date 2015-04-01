2bRAD_GATK_sep27_2013/._GetHighQualVcfs.py                                                          000644  000767  000767  00000000703 12221325446 021655  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2  �     �                                      ATTR      �   �   �                  �   �  %com.apple.metadata:kMDItemWhereFroms   �   :  com.apple.quarantine bplist00�_%Kyle Hernandez <kmhernan84@gmail.com>_Re: tagSeq Counting_Pmessage:%3CCAGKOOYNdrn0dCkbh+dcS-OxV80bDfKPQrwhxfSs+J_D5eHmqug@mail.gmail.com%3E4J                            �q/0003;5245ab27;Mail;E4685887-A892-406E-822D-D094233D8979                                                              2bRAD_GATK_sep27_2013/GetHighQualVcfs.py                                                            000644  000767  000767  00000015544 12221325446 021451  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/env python
# Kyle Hernandez
# GetHighQualVcfs.py - Takes a multi-sample VCF file and creates N VCF files (N = # samples)
#                      of high quality SNPs

import argparse
import os
import re
import time
import sys
import logging
from scipy import stats

###############################################################################
# Class for VariantCallFile

class VariantCallFile(object):
    """Asserts the VCF file is version VCFv4.1"""
    def __init__(self, handle):
	self.handle  = handle   # Input VCF File
        self.meta,\
        self.header,\
        self.samples = self.get_meta(handle)
        self.cols    = []       # List container for columns

    # Record iterator
    def __iter__(self):
	with open(self.handle, 'rU') as f:
            for line in f:
                if not line.startswith('#'):
		    self.cols = line.rstrip().split('\t')
		    yield self

    # Initializer to get metadata and sample data
    def get_meta(self, handle):
        meta = []
        meta_dict = {}
	with open(handle, 'rU') as f:
            for line in f:
                if line.startswith('##'):
                    meta.append(line)
                elif line.startswith('#CHROM'):
                    return meta, line, line.rstrip().split('\t')[9::]
                else:
                    break

    # Member functions
    def is_variant(self):
        """BOOL: Is the current record a variant?"""
        if self.ALT() != '.':
            return True
        return False

    def write_row(self, o):
        """Writes out a row of a VCF file in the correct format"""
        o.write('\t'.join(self.cols) + '\n')

    def write_sample_row(self, o, sample_call):
        """
         Writes out a row for a single-indivual VCF file from a 
         multi-individuals VCF file.
        """
        curr_dat = self.cols[:9]
        o.write('\t'.join(curr_dat) + '\t' + sample_call + '\n')
     
    ##########################################################
    # Getters for each element of the VCF file
    def CHROM(self): 
        try: return int(self.cols[0])
	except: return self.cols[0]

    def POS(self): return int(self.cols[1])

    def ID(self): return self.cols[2]
    
    def REF(self): return self.cols[3]

    def ALT(self): return self.cols[4]

    def QUAL(self): return float(self.cols[5])

    def FILTER(self): return self.cols[6]

    def INFO(self): return self.cols[7]

    def FORMAT(self): return self.cols[8]

    def CALLS(self): return self.cols[9::] # List of genotype calls of size Nsamp 

###############################################################################
# Main application
#

def main():
    """
    Main function wrapper.
    """
    logger.info("Initializing VCF file...")
    # Initialize the VCF object
    vcf_init = VariantCallFile(args.infile)
    
    # Estimate cutoff
    logger.info("Estimating the " + str(args.percentile) + "th percentile cutoff...")
    cutoff = extract_quals(vcf_init, args.percentile)
    logger.info("The cutoff is " + str(cutoff))

    # Filter VCF
    logger.info("Filtering VCF file...")
    filter_file(vcf_init, cutoff, args)

def filter_file(vcf_records, cutoff, args):
    """
    Writes variants with GQ > args.GQ and MAPQ > percentile cutoff
    """
    flag       = 0
    parent_dir = os.path.abspath(args.outdir) + os.sep
    fil_list   = []
    header     = '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT'
    for record in vcf_records:
        # First open all the files for single/multi-sampled VCF.
        # Then write the meta-data and column header with correct sample name.
        if flag == 0:
            fil_list = [open(parent_dir + i + "_HQ.vcf", 'wb') for i in record.samples]
            logger.info("Writing high quality SNPs to " + str(len(fil_list)) + " individual VCFs...")
            [j.write(''.join(record.meta)) for j in fil_list]
            [j.write(header + '\t' + record.samples[n] + '\n') for n,j in enumerate(fil_list)]
            flag = 1
        # Next, we filter out positions with low MAPQ
        if record.is_variant() and record.QUAL() > cutoff:
            # Here we need to then only print out snps to samples where
            # GQ > the cutoff
            # But we only want to print out samples where GT != 0/0 which means it's the reference
            if args.ploidy == 1:
                for n,i in enumerate(record.CALLS()):
                    try:
                        if ':' in i and int(i.split(':')[3]) > args.GQ and i.split(':')[0] != '0':
                            record.write_sample_row(fil_list[n], i)
                    except IndexError:
                        logger.warn(
                          "Weird genotype record '{0}' at CHROM '{1}' POS '{2}' SAMPLE '{3}'".format(
                          i, record.CHROM(), record.POS(), record.samples[n]))
                        pass 
            else:
                for n,i in enumerate(record.CALLS()):
                    try:
                        if ':' in i and int(i.split(':')[3]) > args.GQ and i.split(':')[0] != '0/0':
                            record.write_sample_row(fil_list[n], i)
                    except IndexError:
                        logger.warn(
                          "Weird genotype record '{0}' at CHROM '{1}' POS '{2}' SAMPLE '{3}'".format(
                          i, record.CHROM(), record.POS(), record.samples[n]))
                        pass 
    [j.close() for j in fil_list]

def extract_quals(vcf_records, p):
    """
    Adapted from J. Malcom
    Extract ALTQs for variant loci in vcf record; return percentile score
    """
    AQ = [rec.QUAL() for rec in vcf_records if rec.ALT() != '.']
    return stats.scoreatpercentile(AQ, p)

if __name__ == '__main__':
    start = time.time()

    # Initialize logger
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # Main parser
    parser = argparse.ArgumentParser(prog='GetHighQualVcfs.py',\
	description = 'Split multi-sample VCFs into single sample VCFs of high quality SNPs.')

    # Command line args
    parser.add_argument('-i', '--infile', required=True, type=str,\
	help='Multi-sample VCF file')
    parser.add_argument('-o', '--outdir', required=True, type=str,\
	help='Directory to output HQ VCF files.')
    parser.add_argument('--ploidy', type=int, default=2,\
	help='1 for haploid; 2 for diploid')
    parser.add_argument('--GQ', default=90, type=int,\
	help='Filters out variants with GQ < this limit.')
    parser.add_argument('--percentile', default=90, type=int,\
	help='Reduces to variants with ALTQ > this percentile.')

    # Initialize the parser
    args = parser.parse_args()
   
    # Run script
    logger.info('-'*80)
    logger.info('Kyle Hernandez, 2013, kmhernan84@gmail.com')
    logger.info('GetHighQualVcfs - Get high quality SNPs from a multi-sample VCF files for GATK') 
    logger.info('-'*80)
    main()
     
    logger.info("Finished; Took: " + str(time.time() - start) + " seconds.")
                                                                                                                                                            2bRAD_GATK_sep27_2013/._gatk_walkthrough_GBRRAD_sep2013.txt                                         000644  000767  000767  00000000253 12226613653 024630  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT                              ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/gatk_walkthrough_GBRRAD_sep2013.txt                                           000644  000767  000767  00000034307 12226613653 024422  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         full-blown GATK based on bowtie2 mappings (options: --local -L 16 : with soft-clipping of mismatching ends and seed size 16 
September 25, 2013

The idea is to copy the chunks separated by empty lines below and paste them into your cluster 
terminal window consecutively. 

The lines beginning with hash marks (#) are explanations and additional instructions - 
please make sure to read them before copy-pasting. 

In addition to the scripts coming with this distribution,
you will need the following software installed and available (note: TACC already has them as modules):

python: http://www.python.org/getit/
fastx_toolkit: http://hannonlab.cshl.edu/fastx_toolkit/download.html
bowtie2: http://bowtie-bio.sourceforge.net/index.shtml 
samtools: http://sourceforge.net/projects/samtools/files/
picard: http://sourceforge.net/projects/picard/files/
gatk: http://www.broadinstitute.org/gatk/download
vcftools: http://vcftools.sourceforge.net/ 

==============================================

# (ecogeno2013: skip this one)
# concatenating the reads files (make sure to unzip them first!):
# NOTE: Only run this chunk if your samples are spread over several lanes.
# Assuming your filed have the extension fastq (edit that in the line below if not),
# replace "2b_(.+)_L00" below with the actual pattern to recognize sample
# identifier in the file name. The pattern above will work for file names such as
# Sample_2b_K208_L007_R1.cat.fastq (the identifier is K208)
ngs_concat.pl fastq "2b_(.+)_L00"


# Trimming the reads
# The sampleID parameter here, '3', defines a chunk in the filename (separated
# by underscores) that is to be kept; 
# for example, for a filename like this: Sample_2b_M11_L006_R1.cat.fastq 
# it would be reasonable to specify 'sampleID=3' to keep only 'M11' as a 
# sample identifier. If the sampleID parameter is not specified, the whole filename up to the first dot will be kept.
# NOTE: if you ran ngs_concat.pl (above), run not the next but the second-next line (after removing # symbol) :
2bRAD_trim_launch.pl fastq sampleID=3 > trims
# 2bRAD_trim_launch.pl fq > trims
launcher_creator.py -j trims -n trims -l trimjob
qsub trimjob


# quality filtering using fastx_toolkit
module load fastx_toolkit
ls *.tr0 | perl -pe 's/^(\S+)\.tr0$/cat $1\.tr0 \| fastq_quality_filter -q 20 -p 90 >$1\.trim/' >filt0

# NOTE: run the next line ONLY if your qualities are 33-based (GSAF results are 33-based, BGI results are not):
	cat filt0 | perl -pe 's/filter /filter -Q33 /' > filt
#if you did NOT run the line above, run this one (after removing # symbol):
#	mv filt0 filt

launcher_creator.py -j filt -n filt -l filtjob
qsub filtjob

# Now, edit these lines THROUGHOUT THE TEXT to fit the location and name of your genome reference 
export GENOME_FASTA=myGenome.fasta  # for EcoGeno 2013 class, this would be amil_genome_fold_c.fasta
export GENOME_DICT=myGenome.dict  # same name as genome fasta but with .dict extension; EcoGeno2013: amil_genome_fold_c.dict
export GENOME_PATH=/where/genome/is/
export GENOME_REF=/where/genome/is/myGenome.fasta
#$ -M yourname@utexas.edu

# UNLESS you are working on TACC, edit these accordingly and execute:
export TACC_GATK_DIR=/where/gatk/is/installed/
export TACC_PICARD_DIR=/where/picard/is/installed/
# NOTE that you will have to execute the above two lines every time you re-login!

module load bowtie

# creating genome indexes (default queue):
cd $GENOME_PATH
echo 'bowtie2-build $GENOME_FASTA $GENOME_FASTA' >commands
launcher_creator.py
qsub launcher.sge
module load samtools
samtools faidx $GENOME_FASTA
module load picard


# edit this line so your .dict filename is the same as genome fasta filename
# only with .fasta extension replaced by .dict
export GENOME_DICT=myGenome.dict 
java -jar $TACC_PICARD_DIR/CreateSequenceDictionary.jar R=$GENOME_FASTA  O= $GENOME_DICT


cd /where/reads/are/


# aligning with bowtie2 :
module load bowtie
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
2bRAD_bowtie2_launch.pl '\.trim$' $GENOME_REF > bt2
launcher_creator.py -j bt2 -n maps -l bt2.job -t 3:00:00 -q normal
# calculate the max possible number of cores reasonable: ceiling(Nsamples/wayness)*12  
cat bt2.job | perl -pe 's/12way \d+/4way 396/' > bt2l.job
qsub bt2l.job


ls *.bt2.sam > sams
cat sams | wc -l  
# do you have sams for all your samples?... If not, rerun the chunk above


# making bam files
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
module load picard
module load samtools
cat sams | perl -pe 's/(\S+)\.sam/samtools import \$GENOME_REF $1\.sam $1\.unsorted\.bam && samtools sort $1\.unsorted\.bam $1\.sorted && java -Xmx4g -jar \$TACC_PICARD_DIR\/AddOrReplaceReadGroups\.jar INPUT=$1\.sorted\.bam OUTPUT=$1\.bam RGID=group1 RGLB=lib1 RGPL=illumina RGPU=unit1 RGSM=$1 && samtools index $1\.bam/' >s2b
launcher_creator.py -j s2b -n s2b -l s2b.job -q normal
cat s2b.job | perl -pe 's/12way \d+/4way 396/' > sam2bam.job
qsub sam2bam.job


rm *sorted*
ls *bt2.bam > bams
cat bams | wc -l  
# do you have bams for all your samples?... If not, rerun the chunk above


## WARNING!!! DO NOT RUN THIS FOR RAD!!! (ecogeno2013 - skip this one)
## marking duplicate reads 
# module load picard
# export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
#cat bams | perl -pe 's/(\S+)\.bam/java -Xmx4g -jar \$TACC_PICARD_DIR\/MarkDuplicates\.jar INPUT=$1\.bam OUTPUT=$1\.dedup.bam && java -jar \$TACC_PICARD_DIR\/BuildBamIndex\.jar INPUT=$1\.dedup\.bam/' > dd
#launcher_creator.py -j dd -n dd -l dd.job -q normal
#cat dd.job | perl -pe 's/12way \d+/4way 396/' > ddup.job
#qsub ddup.job
#ls *.dedup.bam > bams


# starting GATK

# realigning around indels:
# step one: finding places to realign:
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
cat bams | perl -pe 's/(\S+)\.bam/java -Xmx4g -jar \$TACC_GATK_DIR\/GenomeAnalysisTK\.jar -T RealignerTargetCreator -R \$GENOME_REF -I $1\.bam -o $1\.intervals/' >intervals
launcher_creator.py -j intervals -n intervals -l inter.job -q normal
cat inter.job | perl -pe 's/12way \d+/2way 396/' > intervals.job
qsub intervals.job


# did it run for all files? is the number of *.intervals files equal the number of *.bam files?
# if not, rerun the chunk above
ll *.intervals | wc -l


# step two: realigning
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
cat bams | perl -pe 's/(\S+)\.bam/java -Xmx4g -jar \$TACC_GATK_DIR\/GenomeAnalysisTK\.jar -T IndelRealigner -R \$GENOME_REF -targetIntervals $1\.intervals -I $1\.bam -o $1\.real.bam -LOD 0\.4/' >realign
launcher_creator.py -j realign -n realign -l realig.job -q normal
cat realig.job | perl -pe 's/12way \d+/2way 396/' > realign.job
qsub realign.job


# did it run for all files? is the number of *.intervals files equal the number of *.bam files?
# if not, rerun the chunk above
ll *.real.bam | wc -l


# launching GATK UnifiedGenotyper (about 3 hours with -nt 24 -nct 1)
# note: it is a preliminary run needed for base quality recalibration,
# we will keep it short by asking to emit only SNPs and not invariant sites or indels
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
ls *real.bam > bams
echo '#!/bin/bash
#$ -V
#$ -cwd
#$ -N unig
#$ -A ecogeno
#$ -pe 1way 48
#$ -q largemem   
#$ -l h_rt=24:00:00
#$ -M yourname@utexas.edu
#$ -m be
java -jar $TACC_GATK_DIR/GenomeAnalysisTK.jar -T UnifiedGenotyper \
-R $GENOME_REF -nt 24 -nct 1 \' >unig
cat bams | perl -pe 's/(\S+\.bam)/-I $1 \\/' >> unig
echo '-o round1.vcf ' >> unig
qsub unig


# creating super-high-confidence (>90 qualty percentile) snp sets for 
# base quality recalibration using Kyle Hernandez's tool:
GetHighQualVcfs.py  -i round1.vcf -o .


# recalibrating quality scores
# step one: creating recalibration reports
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
ls *real.bam > bams
cat bams | perl -pe 's/(\S+)\.real\.bam/java -Xmx4g -jar \$TACC_GATK_DIR\/GenomeAnalysisTK\.jar -T BaseRecalibrator -R \$GENOME_REF -knownSites $1_HQ\.vcf -I $1\.real\.bam -o $1\.real\.recalibration_report.grp/' >bqsr
launcher_creator.py -j bqsr -n bqsr -l bqsrjob -q normal
cat bqsrjob | perl -pe 's/12way \d+/4way 396/' > bqsr.job
qsub bqsr.job


# did it run for all files? is the number of *.grp files equal the number of *.real.bam files?
# if not, rerun the chunk above
ll *.real.bam | wc -l
ll *.grp | wc -l


# step two: rewriting bams according to recalibration reports
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
cat bams | perl -pe 's/(\S+)\.bam/java -Xmx4g -jar \$TACC_GATK_DIR\/GenomeAnalysisTK\.jar -T PrintReads -R \$GENOME_REF -I $1\.bam -BQSR $1\.recalibration_report.grp -o $1\.recal\.bam /' >bqsr2
launcher_creator.py -j bqsr2 -n bqsr2 -l bqsrjob2 -q normal
cat bqsrjob2 | perl -pe 's/12way \d+/4way 396/' > bqsr2.job
qsub bqsr2.job


# did it run for all files? is the number of *.recal.bam files equal the number of *.real.bam files?
# if not, rerun the chunk above
ll *.real.bam | wc -l
ll *.recal.bam | wc -l

ls *.recal.bam > bams


# Second iteration of UnifiedGenotyper (on quality-recalibrated files)
# this time FOR REAL! 
# this takes a looong time if you want to record both variable an invariable sites;
# if you need only SNPs, remove '--output_mode EMIT_ALL_CONFIDENT_SITES'
# in you need indels, run the same process separately with --genotype_likelihoods_model INDEL
# I do not recommend indel tracing for 2bRAD since the tags are too short for confident indels. 
# If you still want to try, note that the subsequent recalibration stages would 
# have do be done separately for indels, 
# and replicatesMatch.pl (at least in its present form) could not be used
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
echo '#!/bin/bash
#$ -V
#$ -cwd
#$ -N unig2
#$ -A ecogeno
#$ -pe 1way 24
#$ -q largemem   
#$ -l h_rt=24:00:00
#$ -M yourname@utexas.edu
#$ -m be
java -jar $TACC_GATK_DIR/GenomeAnalysisTK.jar -T UnifiedGenotyper \
-R $GENOME_REF -nt 24 -nct 1 \
--genotype_likelihoods_model SNP --output_mode EMIT_ALL_CONFIDENT_SITES \' >unig2
cat bams | perl -pe 's/(\S+\.bam)/-I $1 \\/' >> unig2
echo '-o round2.vcf ' >> unig2
qsub unig2

#-------------------------
# alternatively, on Stampede:

export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
echo '#!/bin/bash
#SBATCH -J unig2
#SBATCH -o unig2.o%j
#SBATCH -A tagmap
#SBATCH -n 32
#SBATCH -p largemem   
#SBATCH -t 48:00:00
#SBATCH --mail-user=matz@utexas.edu
#SBATCH --mail-type=end
java -d64 -jar $TACC_GATK_DIR/GenomeAnalysisTK.jar -T UnifiedGenotyper \
-R $GENOME_REF -nt 32 -nct 1 \
--genotype_likelihoods_model SNP --output_mode EMIT_ALL_CONFIDENT_SITES \' >unig2
cat bams | perl -pe 's/(\S+\.bam)/-I $1 \\/' >> unig2
echo '-o round2.vcf ' >> unig2
sbatch unig2

showq -u cmonstr
#-------------------------


# making a tab-delimited table of clone (replicate) sample pairs
nano clonepairs.tab
# ecogeno2013: paste this (make sure there is no empty-line at the end!):
# everyone else: edit accordingly 
K210	K212
K212	K213
K213	K216
K4	O5
K211	K219
M16	M17


# renaming samples in the vcf file, to get rid of trim-shmim etc
cat round2.vcf | perl -pe 's/\.fq\.trim\.bt2//g' | perl -pe 's/\.trim\.bt2//g' >round2.names.vcf


# extracting SNPs that are consistently genotyped in replicates, polymorphic, and have 
# the fraction of alternative allele (falt) relatively high in replicated samples
replicatesMatch.pl vcf=round2.names.vcf replicates=clonepairs.tab polyonly=1 falt=0.15 >vqsrSet.vcf
# 4308673 total SNPs
# 1884356 passed
# 28568 alt alleles
# 22817 polymorphic
# 15612 written


# Recalibrating genotype calls: VQSR
# step one - creating recalibration models (30 min)
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
echo '#!/bin/bash
#$ -V
#$ -cwd
#$ -N vqsr
#$ -A ecogeno
#$ -pe 1way 12
#$ -q development   
#$ -l h_rt=1:00:00
#$ -M matz@utexas.edu
#$ -m be 
java -jar $TACC_GATK_DIR/GenomeAnalysisTK.jar -T VariantRecalibrator \
-R $GENOME_REF -input round2.names.vcf -nt 12 \
-resource:repmatch,known=true,training=true,truth=true,prior=10  vqsrSet.vcf \
-an DP -an InbreedingCoeff -an QD -an MQ -mode SNP \
--target_titv 1.4 -tranche 90.0 -tranche 95.0 -tranche 99.0 -tranche 100 \
-recalFile round2.recal -tranchesFile recalibrate_SNP.tranches -rscriptFile recalibrate_SNP_plots.R 
' > vqsrjob
qsub vqsrjob


# applying recalibration:
module load gatk/2.5.2
export GENOME_REF=/work/01211/cmonstr/amil_genome/amil_genome_fold_c.fasta
echo '#!/bin/bash
#$ -V
#$ -cwd
#$ -N apprec
#$ -A ecogeno
#$ -pe 1way 12
#$ -q development   
#$ -l h_rt=1:00:00
#$ -M you@utexas.edu
#$ -m be
java -jar $TACC_GATK_DIR/GenomeAnalysisTK.jar -T ApplyRecalibration \
-R $GENOME_REF -input round2.names.vcf -nt 12 \
--ts_filter_level 90.0 -mode SNP \
-recalFile round2.recal -tranchesFile recalibrate_SNP.tranches -o gatk_after_vqsr.vcf
' > apprecal
qsub apprecal


# applying filter and selecting loci that are genotyped in 80% or more individuals (--geno), and 
# individuals with >60% of those loci genotyped (--mind)
vcftools --vcf gatk_after_vqsr.vcf --remove-filtered-all --remove Adn.pop --geno 0.8 --mind 0.6 --recode --out gatk_vqsr_filt
# After filtering, kept 132 out of 132 Individuals
# After filtering, kept 1557665 out of a possible 4308673 Sites


# genotypic match between pairs of replicates (this time including the poorer ones, Ni)	
repMatchStats.pl vcf=gatk_vqsr_filt.recode.vcf replicates=clonepairsBig.tab 
#pair	gtyped	match	[ 00	01	11 ]	HetMatch	HomoHetMismatch	HetNoCall	HetsDiscoveryRate
#K210:K212	1519145	1515883(99.8%)	 [99%	0%	0% ]	6656	550	16	0.96	
#K212:K213	1526028	1518806(99.5%)	 [99%	0%	0% ]	6697	536	6	0.96	
#K213:K216	1523350	1510086(99.1%)	 [99%	0%	0% ]	6432	769	20	0.94	
#K4:O5	1344520	1330550(99.0%)	 [99%	0%	0% ]	4667	940	137	0.90	
#K211:K219	1526631	1521250(99.6%)	 [99%	0%	0% ]	6746	473	4	0.97	
#M16:M17	1527024	1520212(99.6%)	 [99%	0%	0% ]	6823	621	13	0.96	
#Ni15:Ni16	1327423	1194527(90.0%)	 [100%	0%	0% ]	1018	5512	491	0.38	
#Ni16:Ni17	1333968	1153377(86.5%)	 [100%	0%	0% ]	876	5225	583	0.36	
#Ni17:Ni18	1269591	1075172(84.7%)	 [100%	0%	0% ]	744	4523	609	0.36	
#Ni15:O166	1327423	1271611(95.8%)	 [100%	0%	0% ]	1144	6959	717	0.36	
#------------------------
#hets called homos depth: 
#lower 25%	3,0
#median		14,0
#upper 75%	34,0


                                                                                                                                                                                                                                                                                                                         2bRAD_GATK_sep27_2013/._launcher_creator.py                                                         000700  000767  000767  00000000253 12215750121 022175  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT                              ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/launcher_creator.py                                                           000700  000767  000767  00000016555 12215750121 021774  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/env python
try:
    import argparse
except:
    print 'Try typing "module load python" and then running this again.'
    import sys
    sys.exit(1)
    
import sys

def file_len(fname):
    f = open(fname)
    for i, l in enumerate(f):
        pass
    return i + 1

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-e', action='store', dest='email', default='yourname@utexas.edu', help='Your email address if you want to receive an email from Lonestar when your job starts and ends. Default=OFF')
    parser.add_argument('-q', action='store', dest='queue', default='development', help='The TACC allocation for job submission. Default="development"')
    parser.add_argument('-t', action='store', dest='time', default='1:00:00', help='The time you want to give to your job. Format: hh:mm:ss')
    parser.add_argument('-a', action='store', dest='allocation', default='ecogeno', help='The TACC allocation for job submission. Default="20120521SSINGS"')
    parser.add_argument('-n', action='store', dest='name', default='default_launcher_job', help='The name of your job. Default="default_launcher_job"')
    parser.add_argument('-j', action='store', dest='job', default='./commands', help='The name of the job file containing your commands. Default="./commands"')
    parser.add_argument('-l', action='store', dest='launcher', default='launcher.sge', help='The name of the *.sge launcher script that will be created. Default="launcher.sge"')
    
    results = parser.parse_args()
    
    if results.name == None:
        print 'You did not give a job name.'
        parser.print_help()
        return
    if results.time == None:
        print 'You did not give a job time.'
        parser.print_help()
        return
    if results.job == None:
        print 'You did not give a job file.'
        parser.print_help()
        return
    if results.launcher == None:
        print 'You did not give a launcher save name.'
        parser.print_help()
        return
    
    
    num_cores = file_len(results.job)
    print 'Job file has %i lines.' % num_cores
    while num_cores % 12 != 0:
        num_cores += 1
    
    print 'Using %i cores.' % num_cores
    
    launcher_file = open(results.launcher, 'w')
    
    if results.email == None:
        launcher_file.write('''\
#!/bin/csh
#
# Simple SGE script for submitting multiple serial
# jobs (e.g. parametric studies) using a script wrapper
# to launch the jobs.
#
# To use, build the launcher executable and your
# serial application(s) and place them in your WORKDIR
# directory.  Then, edit the CONTROL_FILE to specify 
# each executable per process.
#-------------------------------------------------------
#-------------------------------------------------------
# 
#         <------ Setup Parameters ------>
#
#$ -N %s
#$ -pe 12way %i
#$ -q %s
#$ -o %s.o$JOB_ID
#$ -l h_rt=%s
#$ -V
#$ -cwd
#   <------ You MUST Specify a Project String ----->
#$ -A %s
#------------------------------------------------------
#
# Usage:
#	#$ -pe <parallel environment> <number of slots> 
#	#$ -l h_rt=hours:minutes:seconds to specify run time limit
# 	#$ -N <job name>
# 	#$ -q <queue name>
# 	#$ -o <job output file>
#	   NOTE: The env variable $JOB_ID contains the job id. 
#
module load launcher
setenv EXECUTABLE     $TACC_LAUNCHER_DIR/init_launcher 
setenv CONTROL_FILE   %s
setenv WORKDIR        .
# 
# Variable description:
#
#  EXECUTABLE     = full path to the job launcher executable
#  CONTROL_FILE   = text input file which specifies
#                   executable for each process
#                   (should be located in WORKDIR)
#  WORKDIR        = location of working directory
#
#      <------ End Setup Parameters ------>
#--------------------------------------------------------
#--------------------------------------------------------

#----------------
# Error Checking
#----------------

if ( ! -e $WORKDIR ) then
        echo " "
	echo "Error: unable to change to working directory."
	echo "       $WORKDIR"
	echo " "
	echo "Job not submitted."
	exit
endif

if ( ! -f $EXECUTABLE ) then
	echo " "
	echo "Error: unable to find launcher executable $EXECUTABLE."
	echo " "
	echo "Job not submitted."
	exit
endif

if ( ! -f $WORKDIR/$CONTROL_FILE ) then
	echo " "
	echo "Error: unable to find input control file $CONTROL_FILE."
	echo " "
	echo "Job not submitted."
	exit
endif


#----------------
# Job Submission
#----------------

cd $WORKDIR/
echo " WORKING DIR:   $WORKDIR/"

$TACC_LAUNCHER_DIR/paramrun $EXECUTABLE $CONTROL_FILE

echo " "
echo " Parameteric Job Complete"
echo " "
''' % (results.name,
               num_cores,
               results.queue,               
               results.name,
               results.time,
               results.allocation,             
               results.job))
    else:
        launcher_file.write('''\
#!/bin/csh
#
# Simple SGE script for submitting multiple serial
# jobs (e.g. parametric studies) using a script wrapper
# to launch the jobs.
#
# To use, build the launcher executable and your
# serial application(s) and place them in your WORKDIR
# directory.  Then, edit the CONTROL_FILE to specify 
# each executable per process.
#-------------------------------------------------------
#-------------------------------------------------------
# 
#         <------ Setup Parameters ------>
#
#$ -N %s
#$ -pe 12way %i
#$ -q %s
#$ -o %s.o$JOB_ID
#$ -l h_rt=%s
#$ -V
#$ -M %s
#$ -m be
#$ -cwd
#   <------ You MUST Specify a Project String ----->
#$ -A %s
#------------------------------------------------------
#
# Usage:
#	#$ -pe <parallel environment> <number of slots> 
#	#$ -l h_rt=hours:minutes:seconds to specify run time limit
# 	#$ -N <job name>
# 	#$ -q <queue name>
# 	#$ -o <job output file>
#	   NOTE: The env variable $JOB_ID contains the job id. 
#
module load launcher
setenv EXECUTABLE     $TACC_LAUNCHER_DIR/init_launcher 
setenv CONTROL_FILE   %s
setenv WORKDIR        .
# 
# Variable description:
#
#  EXECUTABLE     = full path to the job launcher executable
#  CONTROL_FILE   = text input file which specifies
#                   executable for each process
#                   (should be located in WORKDIR)
#  WORKDIR        = location of working directory
#
#      <------ End Setup Parameters ------>
#--------------------------------------------------------
#--------------------------------------------------------

#----------------
# Error Checking
#----------------

if ( ! -e $WORKDIR ) then
        echo " "
	echo "Error: unable to change to working directory."
	echo "       $WORKDIR"
	echo " "
	echo "Job not submitted."
	exit
endif

if ( ! -f $EXECUTABLE ) then
	echo " "
	echo "Error: unable to find launcher executable $EXECUTABLE."
	echo " "
	echo "Job not submitted."
	exit
endif

if ( ! -f $WORKDIR/$CONTROL_FILE ) then
	echo " "
	echo "Error: unable to find input control file $CONTROL_FILE."
	echo " "
	echo "Job not submitted."
	exit
endif


#----------------
# Job Submission
#----------------

cd $WORKDIR/
echo " WORKING DIR:   $WORKDIR/"

$TACC_LAUNCHER_DIR/paramrun $EXECUTABLE $CONTROL_FILE

echo " "
echo " Parameteric Job Complete"
echo " "
''' % (results.name,
               num_cores,
               results.queue,
               results.name,               
               results.time,
               results.email,
               results.allocation,
               results.job))
    print 'Launcher successfully created. Type "qsub %s" to queue your job.' % results.launcher

if __name__ == '__main__':
    main()
                                                                                                                                                   2bRAD_GATK_sep27_2013/._ngs_concat.pl                                                               000755  000767  000767  00000000253 12221130370 020763  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT!Rch                          ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/ngs_concat.pl                                                                 000755  000767  000767  00000001422 12221130370 020545  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/perl

$usage= "

ngs_concat.pl : 
concatenates files by matching pattern in their names

arg1: common pattern for files
arg2: perl-like pattern in the filename to recognize, 
	  use brackets to specify the unique part

example: ngs_concat.pl 'Sample' 'Sample_(..)'

";

my $ff = shift or die $usage;
my $patt=shift or die $usage;
#print "pattern $patt\n";
opendir THIS, ".";
my @files=grep /$ff/,readdir THIS;
print "files:\n",@files, "\n";
my @ids=();
foreach $file (@files){
	if ($file=~/$patt/) {
		$ii=$1;
#		unless (grep {$_ eq $ii} @ids){ 
#			my $name=$file;
#			my $ccat=$patt;
#			$ccat=~s/\(.+\)/$ii/;
#			$ccat.="*";
			$name=$ii.".fq";
print "$file > $name\n";

			`cat $file >> $name`;
#			push @ids, $ii;
#		}
	}
	else { print "$patt not found in $file\n";}
}

                                                                                                                                                                                                                                              2bRAD_GATK_sep27_2013/._repMatchStats.pl                                                            000755  000767  000767  00000000253 12227137520 021441  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT!Rch                          ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/repMatchStats.pl                                                              000755  000767  000767  00000011376 12227137520 021234  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/perl

my $usage="

Summarizes genotypic match between replicated samples in a vcf file 
(for all non-missing genotypes)

arguments:

vcf=[file name]  input vcf file
replicates=[file name of replicates] - a two column tab-delimited table listing 
                                      pairs of samples that are replicates
";

my $vcf;
my $reps;

if ("@ARGV"=~/vcf=(\S+)/) { $vcf=$1;}
else { die $usage; }
if ("@ARGV"=~/replicates=(\S+)/) { $reps=$1;}
else { die $usage; }

open VCF, $vcf or die "cannot open vcf file $vcf\n";

my @samples;
my @pairs=();
my %indr={};
my @npairs=();
my $r1;
my $r2;
my $s;

my $nreps=0;

my @gtyped=();
my @match=();
my @homomatch=();
my @refhomomatch=();
my @althomomatch=();
my @heteromatch=();
my @mismatch=();
my @homohetmismatch=();
my @allhetmismatch=();
my @nocallhomo;
my @nocallhet;
my @misDP=();
my $dpslot=0;

while (<VCF>) {
	if ($_=~/^#/) {
		if ($_=~/contig/) { next;}
		elsif ($_=~/^#CHROM/){
#			print $_;
			chop;
			@samples=split("\t",$_);
			my @lead=splice (@samples,0,9);
			open REP, $reps or die "cannot open replicates file $reps\n";
			while (<REP>){
				next if ($_!~/\S+/);
				$nreps++;
				chomp;
				($r1,$r2)=split(/\s+/,$_);
				my $collect=0;
				for(my $i=0;my $s=$samples[$i];$i++){
					if ($s eq $r1) { 
						$indr{$r1}=$i;
						$collect++;
					}
					elsif ($s eq $r2) { 
						$indr{$r2}=$i;
						$collect++;
					}
				}
				push @pairs,"$indr{$r1}:$indr{$r2}";
				push @npairs,"$r1:$r2";
				if ($collect<2) { die "cannot locate samples $r1 and/or $r2\n";}
			}
			close REP;
#warn "$nreps replicate pairs\n";
		}
#		else { print $_;}
		next;
	}
	chop;
	$total++;
	my @lin=split("\t",$_);
	if (!$dpslot){
		my $info=$lin[8];
		my @ifields=split(":",$info);
		for(my $ifi=0;$ifi<=$#ifields;$ifi++){
			if ($ifields[$ifi] eq "DP"){
				$dpslot=$ifi;
				last;
			}
		}
#print "@ifields    => DP:$dpslot\n";
	}
	splice(@lin,0,9);
#warn "--------------\n$start[0]_$start[1]\n\n";
	my @rest1;
	my @rest2;
	my $g1;
	my $g2;
	my $a1;
	my $a2;
	my $b1;
	my $b2;
	for(my $p=0;$pp=$pairs[$p];$p++) {
		($r1,$r2)=split(":",$npairs[$p]);
		($i1,$i2)=split(":",$pp);
		($g1,@rest1)=split(":",$lin[$i1]);
		($g2,@rest2)=split(":",$lin[$i2]);
#warn "$r1:$i1\t$g1\t$r2:$i2\t$g2\n";
#		next if ($g1=~/\./ || $g2=~/\./);
		($a1,$a2)=split(/[\/\|]/,$g1);
		($b1,$b2)=split(/[\/\|]/,$g2);
		if ($g1 eq $g2) { 
			next if ($a1=~/\./ && $a2=~/\./);
			$gtyped[$p]++;
			$match[$p]++;
			if ($a1==$a2) { 
				$homomatch[$p]++;
				if ($a1==0) { $refhomomatch[$p]++;}
				else { $althomomatch[$p]++;}
			}
			else { $heteromatch[$p]++;}
		}
	 	else {
	 		if ($a1=~/\./ && $a2=~/\./) {
	 			$nocall[$p]++;
	 			if ($b1==$b2) { $nocallhomo[$p]++;}
	 			else { $nocallhet[$p]++;}
	 		} 
	 		elsif ($b1=~/\./ && $b2=~/\./) {
	 			$gtyped[$p]++;
	 			$nocall[$p]++;
	 			if ($a1==$a2 ) { $nocallhomo[$p]++;}
	 			else { $nocallhet[$p]++;}
	 		} 
			else {
				$gtyped[$p]++;
				$mismatch[$p]++;
				if ($a1==$a2 ) {
					if ($b1==$b2) { 
						$allhomomismatch[$p]++;
					}
					else {
						$homohetmismatch[$p]++;
						push @misDP, $rest1[$dpslot-1];
					}
				}
				else {
					if ($b1==$b2 ) { 
						$homohetmismatch[$p]++;
						push @misDP, $rest2[$dpslot-1];
					}
					else { $allhetmismatch[$p]++; }
				}		
			}
		}
	}
}

@misDP=sort {$a <=> $b} @misDP;

my $mdp25=$misDP[sprintf("%.0F",($#misDP+1)*0.25)];
my $mdp50=$misDP[sprintf("%.0F",($#misDP+1)*0.5)];
my $mdp75=$misDP[sprintf("%.0F",($#misDP+1)*0.75)];
 
print "pair\tgtyped\tmatch\t[ 00\t01\t11 ]\tHetMatch\tHomoHetMismatch\tHetNoCall\tHetsDiscoveryRate\n";
for(my $p=0;$pp=$npairs[$p];$p++) {
	print "$pp\t$gtyped[$p]\t$match[$p](",sprintf("%.1f",100*$match[$p]/$gtyped[$p]),"%)\t [";
	print sprintf("%.0f",100*$refhomomatch[$p]/$match[$p]),"%\t";
	print sprintf("%.0f",100*$heteromatch[$p]/$match[$p]),"%\t";
	print sprintf("%.0f",100*$althomomatch[$p]/$match[$p]),"% ]\t";
	print $heteromatch[$p],"\t";
	print $homohetmismatch[$p],"\t";
	print $nocallhet[$p],"\t";
#	print $nocallhomo[$p],"\t";
#	print $allhetmismatch[$p],"\t";
#	print $allhomomismatch[$p],"\t";
	print sprintf("%.2f",sqrt($heteromatch[$p]/($nocallhet[$p]+$heteromatch[$p]+$homohetmismatch[$p]))),"\t\n";

#	print sprintf("%.1f",100*($refhomohetmismatch[$p]+$althomohetmismatch[$p])/($refhomohetmismatch[$p]+$althomohetmismatch[$p]+$heteromatch[$p])),"%\t";
#	print "$mismatch[$p](",sprintf("%.1f",100*$mismatch[$p]/$gtyped[$p]),"%)\t[ ";
#	print sprintf("%.1f",100*$allhetmismatch[$p]/$mismatch[$p]),"%\t";
#	print sprintf("%.1f",100*$homohetmismatch[$p]/$mismatch[$p]),"%\t[ ";
#	print sprintf("%.1f",100*$refhomohetmismatch[$p]/$homohetmismatch[$p]),"%\t";
#	print sprintf("%.1f",100*$althomohetmismatch[$p]/$homohetmismatch[$p]),"% ]]\n";
}

print "
------------------------
hets called homos depth: 
lower 25%	$mdp25
median		$mdp50
upper 75%	$mdp75

";                                                                                                                                                                                                                                                                  2bRAD_GATK_sep27_2013/._replicatesMatch.pl                                                          000755  000767  000767  00000000253 12227137411 021766  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT!Rch                          ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/replicatesMatch.pl                                                            000755  000767  000767  00000010141 12227137411 021546  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/perl

my $usage="

selects SNPs that have identical genotypes among replicates
A genotype should be identical or missing; the fraction of allowed
missing genotypes is controlled by missing=  argument.

arguments:

vcf=[file name]  input vcf file
replicates=[file name of replicates] - a two column tab-delimited table listing 
                         pairs of samples that are replicates (at least 4 pairs)
matching=[float] required fraction of matching genotypes (missing counts as match), 
                 default 1 (all must match)
missing=[float]  allowed fraction of missing genotypes, default 0.25
altonly=[1|0] only output SNPs showing alternative alleles, for base quality
			  recalibration (BSQR) in GATK.
polyonly=[1|0] output only those passing SNPs that are polymorphic among 
              replicated samples; for variant quality recalibration (VSQR) in GATK. 
              Overrides altonly setting. Default 0
falt=[float] only output SNPs with this fraction of alternative allele. 
             Works with polyonly=1. Default 0
";

my $vcf;
my $reps;
my $missing=0.25;
my $fmatch=1;
my $altonly=0;
my $polyonly=0;
my $falt=0;

if ("@ARGV"=~/vcf=(\S+)/) { $vcf=$1;}
else { die $usage; }
if ("@ARGV"=~/replicates=(\S+)/) { $reps=$1;}
else { die $usage; }
if ("@ARGV"=~/missing=(\S+)/) { $missing=$1;}
if ("@ARGV"=~/matching=(\S+)/) { $fmatch=$1;}
if ("@ARGV"=~/altonly=1/) { $altonly=1;}
if ("@ARGV"=~/polyonly=1/) { $polyonly=1;}
if ("@ARGV"=~/falt=(\S+)/) { $falt=$1;}


open VCF, $vcf or die "cannot open vcf file $vcf\n";

my @samples;
my @pairs=();
my %indr={};
my @npairs=();
my $r1;
my $r2;
my $nreps=0;
my $pass=0;
my $total=0;
my $poly=0;
my $numalt=0;
my $numout=0;

while (<VCF>) {
	if ($_=~/^#/) {
		if ($_=~/contig/) { next;}
		elsif ($_=~/^#CHROM/){
			print $_;
			chop;
			@samples=split("\t",$_);
			my @lead=splice (@samples,0,9);
			open REP, $reps or die "cannot open replicates file $reps\n";
			while (<REP>){
				next if ($_!~/\S+/);
				$nreps++;
				chomp;
				($r1,$r2)=split(/\s+/,$_);
				my $collect=0;
				for(my $i=0;my $s=$samples[$i];$i++){
					if ($s eq $r1) { 
						$indr{$r1}=$i;
						$collect++;
					}
					elsif ($s eq $r2) { 
						$indr{$r2}=$i;
						$collect++;
					}
				}
				push @pairs,"$indr{$r1}:$indr{$r2}";
				push @npairs,"$r1:$r2";
				if ($collect<2) { die "cannot locate samples $r1 and/or $r2\n";}
			}
			close REP;
#warn "$nreps replicate pairs\n";
		}
		else { print $_;}
		next;
	}
	chop;
	$total++;
	my @lin=split("\t",$_);
	my @start=splice(@lin,0,9);
#warn "--------------\n$start[0]_$start[1]\n\n";
	my @rest;
	my $match=0;
	my $miss=0;
	my %seen={};
	my $anum=0;
	my $g1;
	my $g2;
	my $a1;
	my $a2;
	my $nalt=0;
	my $nref=0;
	for(my $p=0;$pp=$pairs[$p];$p++) {
		($r1,$r2)=split(":",$npairs[$p]);
		($i1,$i2)=split(":",$pp);
		($g1,@rest)=split(":",$lin[$i1]);
		($g2,@rest)=split(":",$lin[$i2]);
#warn "$r1:$i1\t$g1\t$r2:$i2\t$g2\n";
		if ($g1=~/\./ || $g2=~/\./) { 
			$miss++;
			$match++;
		}
		elsif ($g1 eq $g2) { 
			$match++;
			($a1,$a2)=split(/\D/,$g1);
			if ($a1=~/[12345]/) { $nalt++;}
			else { $nref++;}
			if ($a2=~/[12345]/) { $nalt++;}			
			else { $nref++;}
#warn "\t\t$a1 $a2\n";
			if (!$seen{$a1}){
				$seen{$a1}=1;
				$anum++;
			}
			if (!$seen{$a2}){ 
				$seen{$a2}=1;
				$anum++;
			}
		}
	}
#warn "\nmatch:$match\nmiss:$miss\nnref:$nref\nnalt:$nalt\nanum:$anum\n\nmatchtest:",$nreps*$fmatch,"\nmisstest:",sprintf("%.2f",$miss/$nreps),"\n\n";
	next if ($match < ($nreps*$fmatch) );
	next if ( ($miss/$nreps) > $missing);
	if ($nalt) { $numalt++;}
	if ($anum>1) { $poly++;}
	if (!$altonly && !$polyonly) { 
		print join("\t",@start)."\t".join("\t",@lin)."\n";
	}
	elsif ($polyonly) {
#warn "poly:\nfalttest:",sprintf("%.2f",$nalt/($nalt+$nref)),"\nfalt:$falt\n\n";
		if ($anum>1 && $nalt/($nalt+$nref)>=$falt) { 	
			$numout++;
			print join("\t",@start)."\t".join("\t",@lin)."\n";
#warn join("\t",@samples)
		}
	}
	elsif ($altonly){
		if ($alt && $nalt/($nalt+$nref)>=$falt) {
			$numout++;
			print join("\t",@start)."\t".join("\t",@lin)."\n";
		}
	}
	$pass++;
}
warn "$total total SNPs\n$pass passed\n$numalt alt alleles\n$poly polymorphic\n$numout written\n\n";	                                                                                                                                                                                                                                                                                                                                                                                                                               2bRAD_GATK_sep27_2013/._trim2bRAD.pl                                                                000755  000767  000767  00000000253 12221337370 020404  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT!Rch                          ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/trim2bRAD.pl                                                                  000755  000767  000767  00000002305 12221337370 020167  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/perl
$usage="

Trims 2b-RAD fastq files to leave only those with  adaptor on the far end and restriction site

arg1: fastq filename
arg2: pattern defining the site, such as \'.{12}CGA.{6}TGC.{12}|.{12}GCA.{6}TCG.{12}\' for BcgI
arg3: (optional) adaptor sequence, default AGATCGGAAGA
arg4: (optional) number of bases to trim off the ends of the reads (corresponding to ligated overhangs), default 0

";

open INP, $ARGV[0] or die $usage;
my $site=$ARGV[1] or die $usage;
my $adap="AGATCGGAAGA";
if ($ARGV[2]){$adap=$ARGV[2];}
my $clip=0;
if ($ARGV[3]){$clip=$ARGV[3];}
my $trim=0;
my $name="";
my $name2="";
my $seq="";
my $qua="";
my $ll=3;
while (<INP>) {
	if ($ll==3 && $_=~/^(\@.+)$/) {
		$name2=$1; 
		if ($seq=~/^($site)$adap/) {
#			if (!$trim) {$trim=length($1)-$clip*2;}
			my $rd=substr($1,$clip,length($1)-$clip*2);
			print "$name\n$rd\n+\n",substr($qua,$clip,length($1)-$clip*2),"\n";
		}
		$seq="";
		$ll=0;
		$qua="";
		@sites=();
		$name=$name2;
	}
	elsif ($ll==0){
		chomp;
		$seq=$_;
		$ll=1;
	}
	elsif ($ll==2) { 
		chomp;
		$qua=$_;
		$ll=3; 
	}
	else { $ll=2;}
}
$name2=$1; 
if ($seq=~/^($site)$adap/) {
	if (!$trim) {$trim=length($1);}
	print "$name\n$1\n+\n",substr($qua,0,$trim),"\n";
}
                                                                                                                                                                                                                                                                                                                           2bRAD_GATK_sep27_2013/._trim2bRAD_2barcodes.pl                                                      000755  000767  000767  00000000253 12223150430 022320  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                             Mac OS X            	   2   y      �    TEXT!Rch                          ATTR       �   �                     �     com.apple.TextEncoding   UTF-8;134217984                                                                                                                                                                                                                                                                                                                                                     2bRAD_GATK_sep27_2013/trim2bRAD_2barcodes.pl                                                        000755  000767  000767  00000005075 12223150430 022112  0                                                                                                    ustar 00c-monster                       c-monster                       000000  000000                                                                                                                                                                         #!/usr/bin/perl
$usage="

Trims 2b-RAD fastq files to leave only those with  adaptor on the far end and restriction site

arg1: fastq filename
arg2: pattern defining the site, such as \'.{12}CGA.{6}TGC.{12}|.{12}GCA.{6}TCG.{12}\' for BcgI
arg3: (optional) in-read barcode that immediately follows the RAD fragment, 
       default \'[ATGC]{4}\'
arg4: (optional) adaptor sequence, default AGATCGGAAG
arg5: (optional) number of bases to trim off the ends of the reads (corresponding to 
       ligated overhangs), default 0
       
other optionals:
minBCcount=[integer] minimum count per in-line barcode to output a separate file. 
				     Default 1000.
sampleID=[integer] the position of name-deriving string in the file name
					if separated by underscores, such as: 
					for input file Sample_RNA_2DVH_L002_R1.cat.fastq
					specifying arg2 as \'3\' would create output 
					file with a name \'2DVH.trim'	
";

open INP, $ARGV[0] or die $usage;
my $site=$ARGV[1] or die $usage;
my $bcod="[ATGC]{4}";
if ($ARGV[2]){$bcod=$ARGV[2];}
my $adap="AGATCGGAAG";
if ($ARGV[3]){$adap=$ARGV[3];}
my $clip=0;
if ($ARGV[4]){$clip=$ARGV[4];}
my $sampleid=100;
if("@ARGV"=~/sampleID=(\d+)/){ $sampleid=$1;}
my $trim=0;
my $name="";
my $name2="";
my $seq="";
my $qua="";
my $minBCcount=1000;
if ("@ARGV"=~/minBCcount=(\d+)/){$minBCcount=$1;}

my $ll=3;
my %data={};
my $counter=0;
while (<INP>) {
	chomp;
	if ($ll==3 && $_=~/^(\@.+)$/) {
		$name2=$1; 
		$counter++;
#print "$seq:";
		if ($seq=~/^($site)($bcod)$adap/) {
#print "$1:$2\n";
			my $rd=substr($1,$clip,length($1)-$clip*2);
			$qua=substr($qua,$clip,length($1)-$clip*2);
			$dline="$name bcd=$2\n$rd\n+\n$qua\n";
			push @{$data{$2}}, $dline ;
#print "$dline\n";
		}
		else {
#print "\n\nNOT FINDING $site:$bcod:$adap\n\n";
		}
#print "-----------\n$counter\n$_\n";
		$seq="";
		$ll=0;
		$qua="";
		@sites=();
		$name=$name2;
	}
	elsif ($ll==0){
		chomp;
		$seq=$_;
		$ll=1;
	}
	elsif ($ll==2) { 
		chomp;
		$qua=$_; 
		$ll=3;
	}
	else { $ll=2;}
}
$name2=$1; 
if ($seq=~/^($site)($bcod)$adap/) {
	my $rd=substr($1,$clip,length($1)-$clip*2);
	$qua=substr($qua,$clip,length($1)-$clip*2);
	$dline="$name bcd=$2\n$rd\n+\n$qua\n";
	push @{$data{$2}}, $dline ;
}

my $outname;
if ($sampleid<100) {
	my @parts=split('_',$ARGV[0]);
	$outname=$parts[$sampleid-1];
}
else { 
	$ARGV[0]=~s/\..+//;
	$outname=$ARGV[0];
}


foreach $bc2 (sort keys %data) {
	next if ($bc2=~/HASH/);
	next if ($#{$data{$bc2}}<$minBCcount);
	my $outname1=$outname."_".$bc2.".tr0";
	open OUT, ">$outname1" or die "cannot create $outname1\n";
	foreach $d (@{$data{$bc2}}) { print {OUT} $d; }
	close OUT;
}

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   