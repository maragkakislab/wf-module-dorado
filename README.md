# wf-module-dorado

Snakemake workflow module to run ONT Dorado basecalling, demultiplexing and
post-processing for experiments organized as one directory per experiment.

This repository provides a reproducible Snakemake pipeline that is primarily
intended to be consumed by other workflows as a module (although it can also run
independently):

- downloads the Dorado basecaller,
- runs Dorado basecalling across experiment POD5 files,
- optionally demultiplexes multiplexed runs,
- converts basecalled BAMs to FASTQ,
- runs pychopper for unstranded kits,
- organizes outputs per-experiment and per-sample under `basecall/` and
    `samples/` respectively.

## Requirements

- Snakemake (>=6 recommended)
- A GPU-equipped machine for Dorado basecalling.

These rules require minimal resources and can be speficied as localrules

```python
localrules: run_all, rename_final_stranded_fastq, get_dorado, demux_get_bam,
            pychopper_merge_trimmed_rescued, get_basecalled_bam_for_sample
```

## How to use in other workflows

In the consuming workflow add a section in the config that includes all required
parameters included in this workflow config file.

In the consuming `config.yml`:
```yaml
# Sample data
DORADO: {
  DOWNLOADS_DIR: "downloads",
  EXP_DIR: "experiments",
  BASECALL_DIR: "basecall",
  SAMPLES_DIR: "samples",
  BIN_VERSION: 'dorado-1.1.1-linux-x64',
  DORADO_RESOURCES: {
    gpu: 2,
    gpu_model: "[gpua100|gpuv100x]",
  },
  DEFAULT_MODEL: 'hac',
  SAMPLE_DATA: {
    'header': ['sample_id', 'experiment_id', 'kit', 'stranded', 'barcode'],
    'data': [
        ['sample1', 'exp1', 'SQK-LSK114', 'false', ''],
    ]
  }
}
```

Then in a consuming snakefile:

```python
module dorado_basecall:
    snakefile:
        github("maragkakislab/wf-module-dorado", path="workflow/Snakefile")
    config:
        config["DORADO"]

use rule * from dorado_basecall as dorado_*

rule run_all:
    input:
        # Basecalled BAM
        SAMPLES_DIR + "/test1/basecall/calls.bam",
        # Basecalled and stranded FASTQ
        SAMPLES_DIR + "/test1/fastq/reads.final.fastq.gz",
```

## Configuration (how to edit `config/config.yml`)

Important keys found in `config/config.yml` (examples):

- `DOWNLOADS_DIR` - where Dorado tarballs / binaries are downloaded (default
    `downloads`).
- `EXP_DIR` - directory containing one subdirectory per experiment. Each
    experiment directory should contain POD5 files and the `EXP_DIR_TRIGGER_FILE`
    (default `origin.txt`) which acts as a trigger for the workflow.
- `BASECALL_DIR` - where per-experiment basecalling outputs are stored.
- `SAMPLES_DIR` - where per-sample outputs are placed.
- `BIN_VERSION` - Dorado binary version to use.
- `DORADO_RESOURCES` - Dorado default GPU resources (Optional)
- `DEFAULT_MODEL`, `CUSTOM_MODELS` - model selection used in `basecall` rule.
- `SAMPLE_DATA` - table describing samples; the `workflow/rules/common.smk`
    code parses this into `samples` and `experiments` objects. The structure is:

    SAMPLE_DATA:
        header: [sample_id, experiment_id, kit, stranded, barcode]
        data:
            - [sample1, exp1, SQK-RNA004]
            - [sample3_1, exp3, SQK-PCB111-24, 'false', 01]

    If multiple samples share the same `experiment_id` they will be treated as
    multiplexed and will be demultiplexed by barcode.
