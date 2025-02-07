#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

params.outdir = 'results'

process run_r_script {
    publishDir "${params.outdir}/r_output", mode: 'copy'
    container 'bioconductor/bioconductor_docker:RELEASE_3_17'

    input:
    path sample_sheet
    path demux_stats
    path run_info

    output:
    path "Reports/*.html", emit: reports, optional: true
    path "r_script_output.log", emit: log

    script:
    """
    mkdir -p Reports
    echo "Current directory: \$(pwd)"
    echo "Contents of current directory:"
    ls -la
    echo "R version:"
    R --version
    echo "Installed R packages:"
    R -e "installed.packages()[,c(1,3)]"
    echo "Running R script..."
    Rscript -e "
    source('/usr/src/app/2demux_ss_sinan.R')
    main('${sample_sheet}', '${demux_stats}', '${run_info}')
    " 2>&1 | tee r_script_output.log
    echo "R script execution completed"
    echo "Contents of r_script_output.log:"
    cat r_script_output.log
    echo "Contents of Reports directory:"
    ls -la Reports/
    """
}

process generate_custom_content {
    output:
    path "custom_content.yaml"

    script:
    """
    cat <<-END_YAML > custom_content.yaml
    custom_data:
        custom_content_section:
            id: 'custom_content_section'
            section_name: 'Custom Content'
            description: 'This is a custom content section'
            plot_type: 'html'
            data: |
                <div id='custom_content_plot'></div>
                <script src='https://cdn.plot.ly/plotly-latest.min.js'></script>
                <script>
                    var data = [{
                        x: ['A', 'B', 'C', 'D'],
                        y: [1, 3, 2, 4],
                        type: 'bar'
                    }];
                    var layout = {title: 'Custom Content Plot'};
                    Plotly.newPlot('custom_content_plot', data, layout);
                </script>
    END_YAML
    """
}

process run_multiqc {
    publishDir "${params.outdir}/multiqc", mode: 'copy'
    container 'ewels/multiqc:latest'

    input:
    path '*'
    path 'custom_content.yaml'

    output:
    path "multiqc_report.html", emit: report

    script:
    """
    echo "Contents of current directory:"
    ls -la
    multiqc . --config custom_content.yaml
    echo "Contents of directory after MultiQC:"
    ls -la
    """
}

workflow {
    // Input channels
    ch_samples = Channel.fromPath("../Reports/SampleSheet.csv")
    ch_stats = Channel.fromPath("../Reports/Demultiplex_Stats.csv")
    ch_run_info = Channel.fromPath("../Reports/RunInfo.xml")
    
    // Run R script
    run_r_script(ch_samples, ch_stats, ch_run_info)
    
    // Generate custom content
    custom_content = generate_custom_content()
    
    // Collect all outputs from run_r_script and include input files
    ch_multiqc_input = run_r_script.out.reports.mix(run_r_script.out.log)
        .mix(ch_samples, ch_stats, ch_run_info)
        .collect()
    
    // Run MultiQC
    run_multiqc(ch_multiqc_input, custom_content)
}