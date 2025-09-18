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


# Create a pandas dataframe from SAMPLE_DATA in config.yml
df_samples = pd.DataFrame(SAMPLE_DATA['data'],
                          columns=SAMPLE_DATA['header'])


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
