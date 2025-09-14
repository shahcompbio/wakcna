/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { CLAIR3                 } from '../modules/nf-core/clair3/main'
include { LONGPHASE_PHASE        } from '../modules/nf-core/longphase/phase/main'
include { WAKHAN_HAPCORRECT      } from '../modules/local/wakhan/hapcorrect/main'
include { TABIX_TABIX            } from '../modules/nf-core/tabix/tabix/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_wakcna_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow WAKCNA {
    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // split ch_samplesheet into a tumor and normal channel
    ch_samplesheet
        .branch { meta, bam, bai ->
            tumor: meta.condition == 'tumor'
            norm: meta.condition == 'normal'
        }
        .set { bam_ch }
    // run clair3 for germline snps
    clair_input_ch = bam_ch.norm.map { meta, bam, bai ->
        tuple(meta, bam, bai, params.clair3_model, [], params.clair3_platform)
    }
    CLAIR3(clair_input_ch, [[id: "ref"], params.fasta], [[id: "ref"], params.fai])
    // run longphase to phase SNPs
    longphase_input_ch = bam_ch.norm
        .join(CLAIR3.out.vcf, by: 0)
        .map { meta, bam, bai, vcf ->
            tuple(meta, bam, bai, vcf, [], [])
        }
    LONGPHASE_PHASE(longphase_input_ch, [[id: "ref"], params.fasta], [[id: "ref"], params.fai])
    // phase correct tumor bam using phased SNPs
    hapcorrect_input_ch = bam_ch.tumor
        .map { meta, bam, bai -> tuple(meta.id, meta, bam) }
        .join(LONGPHASE_PHASE.out.vcf.map { meta, vcf -> tuple(meta.id, meta, vcf) }, by: 0)
        .map { id, tumor_meta, bam, norm_meta, vcf -> tuple(tumor_meta, bam, vcf) }
    hapcorrect_input_ch.view()
    WAKHAN_HAPCORRECT([[id: "ref"], params.fasta], hapcorrect_input_ch)
    // tabix rephased vcf if it exists
    rephased_vcf_ch = WAKHAN_HAPCORRECT.out.rephased_vcf
        .mix(LONGPHASE_PHASE.out.vcf)
        .first()
    rephased_vcf_ch.view()
    // TABIX_TABIX(rephased_vcf_ch)
    // // run whatshap haplotag to tag both tumor and normal bams
    // hap_vcf_ch = rephased_vcf_ch.join(TABIX_TABIX.out.tbi, by: 0)
    // hap_vcf_ch.view()
    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'wakcna_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )
        .set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config = Channel.fromPath(
        "${projectDir}/assets/multiqc_config.yml",
        checkIfExists: true
    )
    ch_multiqc_custom_config = params.multiqc_config
        ? Channel.fromPath(params.multiqc_config, checkIfExists: true)
        : Channel.empty()
    ch_multiqc_logo = params.multiqc_logo
        ? Channel.fromPath(params.multiqc_logo, checkIfExists: true)
        : Channel.empty()

    summary_params = paramsSummaryMap(
        workflow,
        parameters_schema: "nextflow_schema.json"
    )
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml')
    )
    ch_multiqc_custom_methods_description = params.multiqc_methods_description
        ? file(params.multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description)
    )

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true,
        )
    )

    MULTIQC(
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        [],
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions // channel: [ path(versions.yml) ]
}
