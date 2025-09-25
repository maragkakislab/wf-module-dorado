# Rule get_dorado downloads and extracts the specified version of dorado.
rule get_dorado:
    output: 
        tgz = temp(DOWNLOADS_DIR + '/{version}.tar.gz'),
        dorado = DOWNLOADS_DIR + '/{version}/bin/dorado',
    shell:
        """
        curl -L -o {output.tgz} https://cdn.oxfordnanoportal.com/software/analysis/{wildcards.version}.tar.gz

        tar -xf {output.tgz} -C {DOWNLOADS_DIR}/
        """


# extra_options returns additional options to be used in
# basecaller.
def extra_options(experiment):
    additional_options = []
    
    # detection of barcodes
    if experiment.is_barcoded():
        additional_options.append('--kit-name ' + experiment.kit)
    
    # disable adaptor detection (used to orient reads in pychopper)
    if not experiment.is_stranded():
        additional_options.append('--no-trim')

    return " ".join(additional_options),


# model returns the model (plus any mods) to be used by the basecaller.
def model(experiment):
    return ','.join(CUSTOM_MODELS.get(experiment.name, [DEFAULT_MODEL]))


# Rule basecall runs the dorado basecaller.
rule basecall:
    input:
        dorado = DOWNLOADS_DIR + '/' + BIN_VERSION + '/bin/dorado',
        origin = EXP_DIR + "/{e}/" + EXP_DIR_TRIGGER_FILE,
    output:
        BASECALL_DIR + "/{e}/calls.bam"
    params:
        idir = lambda wilds, input: os.path.dirname(input.origin),
        model = lambda wilds: model(experiments[wilds.e]),
        extra_opts = lambda wilds: extra_options(experiments[wilds.e]),
    threads:
        8
    resources:
        gpu = 2,
        gpu_model = "[gpua100|gpuv100x]",
        mem_mb = 64*1024,
        runtime = 8*24*60
    shell:
        """
        {input.dorado} basecaller \
            --recursive \
            --estimate-poly-a \
            {params.extra_opts} \
            {params.model} \
            {params.idir} \
            > {output}
        """

# Rule demux demultiplexes a multiplexed run. The output path will
# contain multiple bam files in the format [kit]_barcode[barcode].bam (e.g.
# SQK-RPB004_barcode01.bam).
rule demux:
    input:
        dorado = DOWNLOADS_DIR + '/' + BIN_VERSION + '/bin/dorado',
        calls = BASECALL_DIR + "/{e}/calls.bam"
    output:
        temp(directory(BASECALL_DIR + "/{e}/demux_tmp/")),
    threads:
        12
    resources:
        mem_mb = 64*1024,
        runtime = 4*24*60
    shell:
        """
        {input.dorado} demux \
            --no-classify \
            --no-trim \
            --threads {threads} \
            --output-dir {output} \
            {input.calls}
        """


# Rule demux_get_bam acts as an interface to the demux rule.
# It describes that the output file names have {kit} and {barcode} wildcards.
# When a file with these wildcards is requested, Snakemake triggers demux
# to create all files in the demux directory.
rule demux_get_bam:
    input:
        BASECALL_DIR + "/{e}/demux_tmp/",
    output:
        BASECALL_DIR + "/{e}/demux/{kit}_barcode{b}.bam",
    shell:
        """
        mv {input}/*_{wildcards.kit}_barcode{wildcards.b}.bam {output}
        """


# bam_from_basecalling identifies and returns the path to the
# basecalled data for a sample. For barcoded samples the path contains two
# extra levels corresponding to the barcode.
def bam_from_basecalling(wilds):
    s = samples[wilds.s]

    if s.is_barcoded():
        # e.g. SQK-RPB004_barcode01.bam
        return os.path.join(BASECALL_DIR, s.parent_exp,
                            "demux", s.kit + '_barcode' + s.barcode + '.bam')

    return os.path.join(BASECALL_DIR, s.parent_exp,
                        "calls.bam")


# Rule get_basecalled_bam_for_sample finds and copies the basecalled bam
# into the sample directory.
rule get_basecalled_bam_for_sample:
    input: bam_from_basecalling
    output: SAMPLES_DIR + "/{s}/basecall/calls.bam"
    resources:
        mem_mb = 1*1024,
        runtime = 1*60,
    threads: 1
    shell:
        """
        ln {input} {output}
        """


# Rule get_fastq_from_basecalled_bam_for_sample finds and converts the
# basecalled bam file corresponding to the requested sample {s} to fastq.
rule get_fastq_from_basecalled_bam_for_sample:
    input: bam_from_basecalling
    output: temp(SAMPLES_DIR + "/{s}/fastq/reads.fastq.gz")
    resources:
        mem_mb = 6*1024,
        runtime = 4*24*60
    threads: 10
    conda:
        "../envs/dorado.yml"
    shell:
        """
        samtools fastq -T '*' --threads {threads} {input} \
                | pigz \
                > {output}
        """


# pychopper_trim_orient_reads uses pychopper to identify and trim the
# ONT barcodes. It also orients the reads 5' to 3'. This is only used for the
# cDNA protocol.
rule pychopper_trim_orient_reads:
    input:
        "{prefix}.fastq.gz"
    output:
        stats_output = "{prefix}.pychop.stats.tsv",
        report = "{prefix}.pychop.report.pdf",
        rescued = "{prefix}.pychop.rescued.fastq.gz",
        unclass = "{prefix}.pychop.unclass.fastq.gz",
        trimmed = "{prefix}.pychop.trimmed.fastq.gz",
    threads: 8
    resources:
        mem_mb = 20*1024,
        runtime = 3*24*60,
        disk_mb = 20*1024
    conda:
        "../envs/dorado.yml"
    shell:
        """
        pychopper \
            -S {output.stats_output} \
            -r {output.report} \
            -k PCS111 \
            -t {threads} \
            -u >(gzip -c > {output.unclass}) \
            -w >(gzip -c > {output.rescued}) \
            {input} \
            - \
            | gzip -c > {output.trimmed}
        """


# pychopper_merge_trimmed_rescued merges the rescued and trimmed reads
# from pychopper into a single file.
rule pychopper_merge_trimmed_rescued:
    input:
        rescued = "{prefix}.pychop.rescued.fastq.gz",
        trimmed = "{prefix}.pychop.trimmed.fastq.gz",
    output:
        "{prefix}.pychopped.fastq.gz"
    threads: 2
    resources:
        mem_mb = 2*1024,
        runtime = 24*60
    shell:
        """
        cat {input.trimmed} {input.rescued} > {output}
        """


# path_to_stranded_fastq identifies and returns the proper stranded fastq file
# depending on whether PCR-cDNA (pychopper had to run) or dRNA-seq was run.
def path_to_stranded_fastq(sample):
    s = sample

    if not s.is_stranded():
        return os.path.join(
            SAMPLES_DIR, s.name, "fastq", "reads.pychopped.fastq.gz")

    return os.path.join(
        SAMPLES_DIR, s.name, "fastq", "reads.fastq.gz")


# publish_final_stranded_fastq simply selects the pychopped or non-pychopped (if
# already stranded) fastq file and moves it to destination.
rule rename_final_stranded_fastq:
    input:
        lambda ws: path_to_stranded_fastq(samples[ws.sample])
    output:
        SAMPLES_DIR + "/{sample}/fastq/reads.final.fastq.gz"
    shell:
        """
        mv {input} {output}
        """
