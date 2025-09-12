//  phase-correct and generates rephased snp VCFs
process WAKHAN_HAPCORRECT {
    tag "${meta1.id}"
    label 'process_high'

    // TODO nf-core: See section in main README for further information regarding finding and adding container addresses to the section below.
    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/wakhan:0.1.2--pyhdfd78af_0'
        : 'biocontainers/wakhan:0.1.2--pyhdfd78af_0'}"

    input:
    tuple val(meta), path(ref_fasta)
    tuple val(meta1), path(bam), path(phased_vcf)

    output:
    // TODO nf-core: Named file extensions MUST be emitted for ALL output channels
    tuple val(meta1), path("**/rephased.vcf.gz"), emit: rephased_vcf
    // TODO nf-core: List additional required output channels/values here
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    wakhan \\
        hapcorrect \\
        ${args} \\
        --threads ${task.cpus} \\
        --reference ${ref_fasta}  \\
        --target-bam ${bam} \\
        --normal-phased-vcf ${phased_vcf} \\
        --genome-name ${meta1.sample}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        wakhan: 0.1.2
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo ${args}

    touch ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        wakhan: \$(wakhan --version)
    END_VERSIONS
    """
}
