import sys
import glob
import os
import pandas as pd
from collections import defaultdict


class sample:
    def __init__(self, name, parent_exp, kit, stranded=True, barcode=None):
        self.name = name
        self.parent_exp = parent_exp
        self.kit = kit
        self.stranded = True if stranded is True or stranded is None else False
        self.barcode = barcode

    def is_barcoded(self):
        if self.barcode is None or self.barcode == '':
            return False
        return True
    
    def is_stranded(self):
        return self.stranded


class experiment:
    def __init__(self, name, samples):
        self.name = name
        self.kit = None
        self.stranded = None
        self.barcoded = None
        self.samples = samples
        self._process_samples()

    def _process_samples(self):
        self._process_kits()
        self._process_strandedness()
        self._process_barcodes()
    
    def _process_kits(self):
        kits = set(s.kit for s in self.samples)
        if len(kits) == 1:
            self.kit = kits.pop()
        else:
            raise ValueError(
                f"Experiment '{self.name}' has multiple kits: {', '.join(kits)}.")
    
    def _process_strandedness(self):
        stranded_statuses = [s.is_stranded() for s in self.samples]
        if all(stranded_statuses):
            self.stranded = True
        elif not any(stranded_statuses):
            self.stranded = False
        else:
            raise ValueError(
                f"Experiment '{self.name}' has a mix of stranded "
                 "and unstranded samples.")

    def _process_barcodes(self):
        # If all barcodes are neither None nor empty, the experiment is 
        # barcoded.
        barcode_statuses = [s.is_barcoded() for s in self.samples]
        if all(barcode_statuses):
            self.barcoded = True
        elif not any(barcode_statuses):
            self.barcoded = False
        else:
            raise ValueError(
                f"Experiment '{self.name}' has a mix of barcoded "
                 "and unbarcoded samples.")

    def is_barcoded(self):
        return self.barcoded
    
    def is_stranded(self):
        return self.stranded


def create_dataframe_from_SAMPLE_DATA(data):
    records = [dict(zip(data['header'], row)) for row in data['data']]
    for rec in records: # Convert 'true'/'false' to boolean True/False
        for k, v in rec.items():
            if isinstance(v, str):
                if v.lower() == 'true':
                    rec[k] = True
                elif v.lower() == 'false':
                    rec[k] = False
    df = pd.DataFrame.from_records(records, columns=data['header'])
    # Use None for empty values.
    df = df.astype(object).where(pd.notna(df), None)
    return df


def validate_dataframe(df):
    required_columns = {'sample_id', 'experiment_id', 'kit'}
    missing_columns = required_columns - set(df.columns)
    if missing_columns:
        raise ValueError(
            f"Missing required columns in SAMPLE_DATA: "
            f"{', '.join(missing_columns)}")
    
    # Check for duplicate sample IDs
    if df['sample_id'].duplicated().any():
        duplicates = df[df['sample_id'].duplicated()]['sample_id'].tolist()
        raise ValueError(
            f"Duplicate sample IDs found in SAMPLE_DATA: "
            f"{', '.join(duplicates)}")
    
    # Check for empty kit values
    if df['kit'].isnull().any() or (df['kit'] == '').any():
        raise ValueError("Some samples have empty 'kit' values in SAMPLE_DATA.")


def samples_dic_from_dataframe(df):
    # Create a dictionary with samples.
    samples = {}
    for _, row in df.iterrows():
        s = sample(name = row['sample_id'],
                   parent_exp = row['experiment_id'],
                   kit = row['kit'],
                   stranded = row.get('stranded', True),
                   barcode = row.get('barcode', None))
        samples[s.name] = s
    return samples


def experiments_dic_from_samples(samples):
    # Group samples by experiment
    exp_samples = defaultdict(list)
    for s in samples.values():
        exp_samples[s.parent_exp].append(s)

    # Create experiments dictionary
    experiments = {
        exp_name: experiment(
            name=exp_name,
            samples=sample_list
        )
        for exp_name, sample_list in exp_samples.items()
    }
    return experiments


# Read sample data from SAMPLE_DATA variable
df = create_dataframe_from_SAMPLE_DATA(SAMPLE_DATA)
validate_dataframe(df)
samples = samples_dic_from_dataframe(df)
experiments = experiments_dic_from_samples(samples)
