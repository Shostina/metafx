#!/usr/bin/env bash
##########################################################################################
## MetaFX chisq module to extract top N chi-squared significant k-mers from metagenomes ##
##########################################################################################

help_message () {
    echo ""
    echo "$(metafx -v)"
    echo "MetaFX chisq module – supervised feature extraction using top significant k-mers by chi-squared test"
    echo "Usage: metafx chisq [<Launch options>] [<Input parameters>]"
    echo ""
    echo "Launch options:"
    echo "    -h | --help                       show this help message and exit"
    echo "    -t | --threads       <int>        number of threads to use [default: all]"
    echo "    -m | --memory        <MEM>        memory to use (values with suffix: 1500M, 4G, etc.) [default: 90% of free RAM]"
    echo "    -w | --work-dir      <dirname>    working directory [default: workDir/]"
    echo ""
    echo "Input parameters:"
    echo "    -k | --k             <int>        k-mer size (in nucleotides, maximum value is 31) [mandatory]"
    echo "    -i | --reads-file    <filename>   tab-separated file with 2 values in each row: <path_to_file>\t<category> [mandatory]"
    echo "    -n | --num-kmers     <int>        number of most specific k-mers to be extracted [mandatory]"
    echo "    -b | --bad-frequency <int>        maximal frequency for a k-mer to be assumed erroneous [default: 1]"
    echo "         --depth         <int>        Depth of de Bruijn graph traversal from pivot k-mers in number of branches [default: 1]"
    echo "         --kmers-dir     <dirname>    directory with pre-computed k-mers for samples in binary format [optional]"
    echo "         --skip-graph                 if TRUE skip de Bruijn graph and fasta construction from components [default: False]"
    echo "";}


# Paths to pipelines and scripts
mfx_path=$(which metafx)
bin_path=${mfx_path%/*}
SOFT=${bin_path}/metafx-scripts
PIPES=${bin_path}/metafx-modules
pwd=`dirname "$0"`

comment () { ${SOFT}/pretty_print.py "$1" "-"; }
warning () { ${SOFT}/pretty_print.py "$1" "*"; }
error   () { ${SOFT}/pretty_print.py "$1" "*"; exit 1; }



w="workDir"
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -h|--help)
    help_message
    exit 0
    ;;
    -k|--k)
    k="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--bad-frequency)
    b="$2"
    shift
    shift
    ;;
    -i|--reads-file)
    i="$2"
    shift
    shift
    ;;
    --kmers-dir)
    kmers="$2"
    shift
    shift
    ;;
    
    -n|--num-kmers)
    nBest="$2"
    shift
    shift
    ;;
    --depth)
    depth="$2"
    shift
    shift
    ;;
    
    -m|--memory)
    m="$2"
    shift
    shift
    ;;
    -t|--threads)
    p="$2"
    shift
    shift
    ;;
    -w|--work-dir)
    w="$2"
    shift
    shift
    ;;
    --skip-graph)
    skipGraph=true
    shift
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


cmd="${PIPES}/metafast.sh "
if [[ $k ]]; then
    cmd+="-k $k "
fi
if [[ $m ]]; then
    cmd+="-m $m "
fi
if [[ $p ]]; then
    cmd+="-p $p "
fi



# ==== Step 1 ====
if [[ ${kmers} ]]; then
    kmersDir="${kmers}"
    mkdir ${w}
    comment "Skipping step 1: will use provided k-mers"
else
    kmersDir="$w/kmers/kmers"
    comment "Running step 1: counting k-mers for samples"
    cmd1=$cmd
    cmd1+="-t kmer-counter-many "
    if [[ ${b} ]]; then
        cmd1+="-b ${b} "
    fi
    if [[ ${i} ]]; then
        cmd1+="-i $(cut -f1 ${i} | tr '\n' ' ') "
    fi
    
    cmd1+="-w ${w}/kmers/"

    echo "$cmd1"
    $cmd1
    if [[ $? -eq 0 ]]; then
        comment "Step 1 finished successfully!"
    else
        error "Error during step 1!"
        exit 1
    fi
fi



# ==== Step 2 ====
comment "Running step 2: extracting statistically-significant k-mers and corresponding ranks"

python3 ${SOFT}/parse_samples_categories.py ${i} > ${w}/categories_samples.tsv
python3 ${SOFT}/get_samples_categories.py ${w}
n_cat=$(wc -l < ${w}/categories_samples.tsv)
if [[ ${n_cat} -lt 2 ]]; then
    echo "Found only ${n_cat} categories in ${i} file. Provide at least 2 categories of input samples!"
    error "Error during step 2!"
    exit 1
fi

cmd2="${PIPES}/metafast.sh "
if [[ $m ]]; then
    cmd2+="-m $m "
fi
if [[ $p ]]; then
    cmd2+="-p $p "
fi


if [[ ${n_cat} -lt 4 ]]; then # 2 or 3 categories
    cmd2+="-t top-stats-kmers "
    
    if [[ ${b} ]]; then
        cmd2+="-b ${b} "
    fi
    
    
    if [[ ${nBest} ]]; then
        cmd2+="--num-kmers ${nBest} "
    fi
    
    IFS=$'\n' read -d '' -ra cat_samples <<< "$(cut -d$'\t' -f2 ${w}/categories_samples.tsv)"
    IFS=$'\n' read -d '' -ra cat_names <<< "$(cut -d$'\t' -f1 ${w}/categories_samples.tsv)"
    
    tmp="${kmersDir}/${cat_samples[0]// /.kmers.bin ${kmersDir}/}.kmers.bin "
    cmd2+="--a-kmers $tmp"
    tmp="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
    cmd2+="--b-kmers $tmp"
    
    AMOUNT="two"
    if [[ ${n_cat} -eq 3 ]]; then
        tmp="${kmersDir}/${cat_samples[2]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        cmd2+="--c-kmers $tmp"
        AMOUNT="three"
    fi
    
    cmd2+="-w ${w}/statistic_kmers_all/"
    
    echo "${cmd2}"
    ${cmd2}
    if [[ $? -eq 0 ]]; then
        echo "Processed ${AMOUNT} categories of samples: ${cat_names[@]}"
    else
        error "Error during step 2!"
        exit 1
    fi
else # 4+ categories
    cmd2+="-t top-stats-kmers "
    if [[ ${b} ]]; then
        cmd2+="-b ${b} "
    fi
    
    if [[ ${nBest} ]]; then
        cmd2+="--num-kmers ${nBest} "
    fi
    
    while read line ; do
        IFS=$'\t' read -ra cat_samples <<< "${line}"
        echo "Processing category ${cat_samples[0]}"
        
        cmd2_i=$cmd2
        
        tmp="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        cmd2_i+="--a-kmers $tmp"
        tmp="${kmersDir}/${cat_samples[2]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        cmd2_i+="--b-kmers $tmp"
        cmd2_i+="-w ${w}/statistic_kmers_${cat_samples[0]}/"

        echo "${cmd2_i}"
        ${cmd2_i}
        if [[ $? -eq 0 ]]; then
            echo "Processed category ${cat_samples[0]}"
        else
            error "Error during step 2!"
            exit 1
        fi
    done<${w}/categories_samples.tsv
fi


if [[ $? -eq 0 ]]; then
    comment "Step 2 finished successfully!"
else
    error "Error during step 2!"
    exit 1
fi


# ==== Step 3 ====
comment "Running step 3: extracting graph components around group-specific k-mers"

cmd3=$cmd
cmd3+="-t component-extractor "

if [[ ${depth} ]]; then
    cmd3+="--depth ${depth} "
fi
if [[ ${n_cat} -lt 4 ]]; then # 2 or 3 categories
    IFS=$'\n' read -d '' -ra cat_samples <<< "$(cut -d$'\t' -f2 ${w}/categories_samples.tsv)"
    IFS=$'\n' read -d '' -ra cat_names <<< "$(cut -d$'\t' -f1 ${w}/categories_samples.tsv)"
    echo "Processing ${AMOUNT} categories of samples: ${cat_names[@]}"
    
    cmd3_i=$cmd3
    tmp="${w}/statistic_kmers_all/kmers/top_${nBest}_chi_squared_specific.kmers.bin "
    cmd3_i+="--pivot $tmp"
    tmp="${kmersDir}/${cat_samples[0]// /.kmers.bin ${kmersDir}/}.kmers.bin "
    tmp+="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
    if [[ ${n_cat} -eq 3 ]]; then
        tmp+="${kmersDir}/${cat_samples[2]// /.kmers.bin ${kmersDir}/}.kmers.bin "
    fi
    cmd3_i+="-i $tmp"
    cmd3_i+="-w ${w}/components_all/"
    
    echo "${cmd3_i}"
    ${cmd3_i}
    if [[ $? -eq 0 ]]; then
        echo "Processed ${AMOUNT} categories of samples: ${cat_names[@]}"
    else
        error "Error during step 3!"
        exit 1
    fi
else # 4+ categories
    while read line ; do
        IFS=$'\t' read -ra cat_samples <<< "${line}"
        echo "Processing category ${cat_samples[0]}"
        
        cmd3_i=$cmd3
        tmp="${w}/statistic_kmers_${cat_samples[0]}/kmers/top_${nBest}_chi_squared_specific.kmers.bin "
        cmd3_i+="--pivot $tmp"
        tmp="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        cmd3_i+="-i $tmp"
        cmd3_i+="-w ${w}/components_${cat_samples[0]}/"

        
        echo "${cmd3_i}"
        ${cmd3_i}
        if [[ $? -eq 0 ]]; then
            echo "Processed category ${cat_samples[0]}"
        else
            error "Error during step 3!"
            exit 1
        fi
    done<${w}/categories_samples.tsv
fi

if [[ $? -eq 0 ]]; then
    comment "Step 3 finished successfully!"
else
    error "Error during step 3!"
    exit 1
fi



# ==== Step 4 ====
comment "Running step 4: calculating features as coverage of components by samples"

cmd4=$cmd
cmd4+="-t features-calculator "

if [[ ${n_cat} -lt 4 ]]; then # 2 or 3 categories
    IFS=$'\n' read -d '' -ra cat_samples <<< "$(cut -d$'\t' -f2 ${w}/categories_samples.tsv)"
    IFS=$'\n' read -d '' -ra cat_names <<< "$(cut -d$'\t' -f1 ${w}/categories_samples.tsv)"
    echo "Processing ${AMOUNT} categories of samples: ${cat_names[@]}"
    
    cmd4_i=$cmd4
    cmd4_i+="-cm ${w}/components_all/components.bin "
    cmd4_i+="-ka ${kmersDir}/*.kmers.bin "
    cmd4_i+="-w ${w}/features_all/"
    
    echo "${cmd4_i}"
    ${cmd4_i}
    if [[ $? -eq 0 ]]; then
        echo "Processed ${AMOUNT} categories of samples: ${cat_names[@]}"
    else
        error "Error during step 4"
        exit 1
    fi
    
    echo "all" > ${w}/tmp
    python3 ${SOFT}/join_feature_vectors.py ${w} ${w}/tmp
    if [[ $? -eq 0 ]]; then
        echo "Feature table saved to ${w}/feature_table.tsv"
    else
        error "Error during step 4!"
        exit 1
    fi
    rm ${w}/tmp
else
    while read line ; do
        IFS=$'\t' read -ra cat_samples <<< "${line}"
        echo "Processing category ${cat_samples[0]}"
        
        cmd4_i=$cmd4
        cmd4_i+="-cm ${w}/components_${cat_samples[0]}/components.bin "
        cmd4_i+="-ka ${kmersDir}/*.kmers.bin "
        cmd4_i+="-w ${w}/features_${cat_samples[0]}/"

        
        echo "${cmd4_i}"
        ${cmd4_i}
        if [[ $? -eq 0 ]]; then
            echo "Processed category ${cat_samples[0]}"
        else
            error "Error during step 4"
            exit 1
        fi
    done<${w}/categories_samples.tsv

    python3 ${SOFT}/join_feature_vectors.py ${w} ${w}/categories_samples.tsv
    if [[ $? -eq 0 ]]; then
        echo "Feature table saved to ${w}/feature_table.tsv"
    else
        error "Error during step 4!"
        exit 1
    fi
fi

if [[ $? -eq 0 ]]; then
    comment "Step 4 finished successfully!"
else
    error "Error during step 4!"
    exit 1
fi



# ==== Step 5 ====
if [[ ${skipGraph} ]]; then 
    comment "Skipping step 5: no de Bruijn graph and fasta sequences construction"
else
    comment "Running step 5: transforming binary components to fasta sequences and de Bruijn graph"

    cmd5=$cmd
    cmd5+="-t comp2graph "

    if [[ ${n_cat} -lt 4 ]]; then # 2 or 3 categories
        IFS=$'\n' read -d '' -ra cat_samples <<< "$(cut -d$'\t' -f2 ${w}/categories_samples.tsv)"
        IFS=$'\n' read -d '' -ra cat_names <<< "$(cut -d$'\t' -f1 ${w}/categories_samples.tsv)"
        echo "Processing ${AMOUNT} categories of samples: ${cat_names[@]}"
        
        cmd5_i=$cmd5
        cmd5_i+="-cf ${w}/components_all/components.bin "
        tmp="${kmersDir}/${cat_samples[0]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        tmp+="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        if [[ ${n_cat} -eq 3 ]]; then
            tmp+="${kmersDir}/${cat_samples[2]// /.kmers.bin ${kmersDir}/}.kmers.bin "
        fi
        cmd5_i+="-i $tmp"
        cmd5_i+="-cov "
        cmd5_i+="-w ${w}/contigs_all/"
        
        echo "${cmd5_i}"
        ${cmd5_i}
        
        python3 ${SOFT}/graph2contigs.py ${w}/contigs_all/
        
        if [[ $? -eq 0 ]]; then
            echo "Processed ${AMOUNT} categories of samples: ${cat_names[@]}"
        else
            error "Error during step 5"
            exit 1
        fi
    else
        while read line ; do
            IFS=$'\t' read -ra cat_samples <<< "${line}"
            echo "Processing category ${cat_samples[0]}"
            
            cmd5_i=$cmd5
            cmd5_i+="-cf ${w}/components_${cat_samples[0]}/components.bin "
            tmp="${kmersDir}/${cat_samples[1]// /.kmers.bin ${kmersDir}/}.kmers.bin "
            cmd5_i+="-i $tmp"
            cmd5_i+="-cov "
            cmd5_i+="-w ${w}/contigs_${cat_samples[0]}/"

            
            echo "${cmd5_i}"
            ${cmd5_i}
            
            python3 ${SOFT}/graph2contigs.py ${w}/contigs_${cat_samples[0]}/
            
            if [[ $? -eq 0 ]]; then
                echo "Processed category ${cat_samples[0]}"
            else
                error "Error during step 5"
                exit 1
            fi
        done<${w}/categories_samples.tsv
    fi
    
    if [[ $? -eq 0 ]]; then
        comment "Step 5 finished successfully!"
    else
        error "Error during step 5!"
        exit 1
    fi
fi


comment "MetaFX chisq module finished successfully!"
exit 0

