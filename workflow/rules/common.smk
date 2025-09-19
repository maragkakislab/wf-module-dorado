import sys
import glob
import os
import pandas as pd


class sample:
    def __init__(self, name, parent_exp, kit, barcode=None):
        self.name = name
        self.kit = kit
        self.parent_exp = parent_exp
        self.barcode = barcode

    def is_barcoded(self):
        if self.barcode is None:
            return False
        return True

    def is_unstranded(self):
        if self.kit in UNSTRANDED_KITS:
            return True
        return False


class experiment:
    def __init__(self, name, kit):
        self.name = name
        self.kit = kit
        self.samples = []

    def is_unstranded(self):
        for s in self.samples:
            if s.is_unstranded():
                return True
        return False

    def is_barcoded(self):
        for s in self.samples:
            if s.is_barcoded():
                return True
        return False


# Create a pandas dataframe from SAMPLE_DATA in config.yml. Use None for empty
# values.
records = [dict(zip(SAMPLE_DATA['header'], row)) for row in SAMPLE_DATA['data']]
df_samples = pd.DataFrame.from_records(records, columns=SAMPLE_DATA['header'])
df_samples = df_samples.astype(object).where(pd.notna(df_samples), None)


# Create a dictionary with samples and experiments.
samples = {}
for _, row in df_samples.iterrows():
    s = sample(
        name = row['sample_id'],
        parent_exp = row['experiment_id'],
        kit = row['kit'],
        barcode = row.get('barcode', None))
    samples[s.name] = s


experiments = {}
for s in samples.values():
    if s.parent_exp not in experiments:
        experiments[s.parent_exp] = experiment(name = s.parent_exp, kit = s.kit)
    experiments[s.parent_exp].samples.append(s)
