#!/bin/bash
## specify params
outdir=$HOME/Library/CloudStorage/OneDrive-MemorialSloanKetteringCancerCenter/SarcAtlas/wakcna/test
pipelinedir=$HOME/VSCodeProjects/shahcompbio-wakcna
mkdir -p ${outdir}
cd ${outdir}

nextflow run ${pipelinedir}/main.nf \
    -profile arm,docker,test \
    -work-dir ${outdir}/work \
    --outdir ${outdir} \
    -resume
