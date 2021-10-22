#!/bin/bash
#set -x
#set -e

#entete generique fichier sourceable ?
export TSTAMP=$(date +%s)                    #nom du script
export SCRIPTNAME=$(basename $0)             #date de reference unique si besoin de plusieurs nommages
export MEM=/dev/shm/${SCRIPTNAME}_${TSTAMP}  #espace temporaire en mémoire
export BASEDIR=$(dirname $(readlink -f $0))  #repertoire où se situe le script        
export MAXINT=9223372036854775807
mkdir -p ${MEM}

function is_incron {
  #return 0 if launched by cron or process in cron
  #return 1 if manually lanched
  MYPID=$$
  CRON_IS_PARENT=0
  CRONPIDS=$(ps ho %p -C crond)
  CPID=$MYPID
  while [ $CRON_IS_PARENT -ne 1 ] && [ $CPID -ne 1 ] ; do
        CPID_STR=$(ps ho %P -p $CPID)
        CPID=$(($CPID_STR))
        for CRONPID in $CRONPIDS ; do
                [ $CRONPID -eq $CPID ] && CRON_IS_PARENT=1
        done
  done
  if [ "$CRON_IS_PARENT" == "1" ]; then
        echo "0"
  else
        echo "1"
  fi
  
}
export -f is_incron

if [[ $(is_incron) == 0 ]]; then
  LAUNCHED='launched by cron'
else
  LAUNCHED='launched manually'
fi

# fin generique


params="$(getopt -o hp:s:o:n: -l help,partition:,state:,output:,nodes: --name "$0" -- "$@")"
eval set -- "$params"
while true
do
    case "$1" in
        -p|--partition)
            part=$2
            shift 2
            ;;
         -o|--output)
            output=$2
            shift 2
            ;;
        -s|--state)
            state=$2
            shift 2
            ;;
        -n|--nodes)
            nodes=$2
            shift 2
            ;;
        -h|--help)
	    echo "return list of nodes with last endtime of running jobs"
            echo "Syntax "
	    echo "end_exec [-p or --partition= <slurm partition>] "
	    echo "         [-s or --state= <filter_state_of_nodes>]" 
            echo "         [-o or --output= <output_file>]"
            echo "         [-n or --nodes= <nodes>]"
	    echo "         [-h or --help] "
	    echo " -s or --state= <filter_state_of_nodes> : List nodes only having the given state(s).  "
	    echo "                                          Multiple states may be comma separated and the comparison is case"
            echo "                                          insensitive.  Possible values include (case insensitive): ALLOC, "
	    echo "                                          ALLOCATED,  COMP,  COMPLETING,  DOWN,  DRAIN(for  node  in  DRAINING"
	    echo "                                          or DRAINED states), DRAINED, DRAINING, ERR, ERROR, FAIL, FUTURE, FUTR,"
	    echo "                                          IDLE, MAINT,MIX, MIXED, NO_RESPOND, NPC, PERFCTRS, POWER_DOWN, POWER_UP,"
	    echo "                                          RESV, RESERVED, UNK, and  UNKNOWN. Default is all"
	    echo "                                          If used with --nodes, it will reduce the given list and it could display nothing"
            echo " [-p or --partition= <slurm partition>] : List nodes only belonging to the given partition(s)."
	    echo "                                          Incompatible with --nodes."
	    echo "                                          Multiple partitions are separated by commas. Default is all"
	    echo " [-o or --output= <output_file>]        : Absolute path of outputfile. Default is ./final"
	    echo " [-n or --nodes= <nodes>]               : List only the given node(s). Incompatible with --partition"
	    echo " [-h or --help]                         : Print this help."
	    
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Not implemented: $1" >&2
            exit 1
            ;;
    esac
done

if [ ! -z ${part+x} ] && [ ! -z ${node+x} ] ; then
   echo "--nodes (or -n) and --partition (or - p) are incompatible. Choose one or the other."
   exit 1
fi

if [ -z ${part+x} ];then
   if  [ -z ${nodes+x} ];then
      cmd_sq="squeue -O 'jobid,endtime,state,Timeleft,nodelist:60' | grep RUNNING > ${MEM}/raw"
      if [ -z ${state+x} ];then
        cmd_sinf="sinfo -Nelh > ${MEM}/sinfo"
      else
        cmd_sinf="sinfo -Nelh -t ${state} > ${MEM}/sinfo" 
      fi
   else
      cmd_sq="squeue -w ${nodes} -O 'jobid,endtime,state,Timeleft,nodelist:60' | grep RUNNING > ${MEM}/raw"   
      if [ -z ${state+x} ];then
         cmd_sinf="sinfo -Nelh -n $nodes > ${MEM}/sinfo"
      else
         cmd_sinf="sinfo -Nelh -n $nodes -t ${state} > ${MEM}/sinfo"
      fi   
   fi 
else
   cmd_sq="squeue -p ${part} -O 'jobid,endtime,state,Timeleft,nodelist:60' | grep RUNNING > ${MEM}/raw"
   if [ -z ${state+x} ];then
     cmd_sinf="sinfo -Nelh  -p ${part} > ${MEM}/sinfo" 
   else
     cmd_sinf="sinfo -Nelh  -p ${part} -t ${state} > ${MEM}/sinfo" 
   fi
fi

if [ -z ${output+x} ]; then mkdir -p ${BASEDIR}/LOGS ;output="${BASEDIR}/LOGS/${TSTAMP}_sinfo_w_end_exec_time.log"; fi


eval ${cmd_sq}&  
eval ${cmd_sinf}&
wait

awk '{print $5}' ${MEM}/raw > ${MEM}/nodes
for i in $(cat ${MEM}/nodes); do nodeset -e $i ;done > ${MEM}/nodesex
rm ${MEM}/nodes
awk '{print $4}' ${MEM}/raw > ${MEM}/timeleft


for i in $(cat ${MEM}/timeleft)
do
  
  if [ $i == "UNLIMITED" ]; then
    TL=${MAXINT} 
  else
    if [[ $i == *"-"* ]]; then
      DD=$(echo $i|cut -d'-' -f 1)
      HHMMSS=$(echo $i|cut -d'-' -f 2)
      TL=$(( $DD * 24 * 3600 ))
    else
      HHMMSS=$i
      TL=0
    fi 
    HH=$(echo $HHMMSS|cut -d':' -f 1)
    MM=$(echo $HHMMSS|cut -d':' -f 2)
    SS=$(echo $HHMMSS|cut -d':' -f 3)
    TL=$((  ${TL#0} + ${HH#0} * 3600 + ${MM#0} * 60 + ${SS#0}  ))
 
  fi 
  echo $TL     
done > ${MEM}/tlex

awk '{print $1, $2, $3}' ${MEM}/raw > ${MEM}/jobs_info
paste ${MEM}/jobs_info ${MEM}/tlex  ${MEM}/nodesex > ${MEM}/final

for n in $(awk '{print $1}' ${MEM}/sinfo )
do 
  ret=$( grep $n ${MEM}/final > /dev/null;echo $? ) 
  if [[ $ret == 1  ]]; then
     echo "NOJOBS"
  else
    grep $n ${MEM}/final | sort -n -k 4 | tail -1 | awk '{print $1,$2,$4}'
  fi
done > ${MEM}/tlex_by_nodes

paste  ${MEM}/sinfo  ${MEM}/tlex_by_nodes > $output

#fin generique
rm -rf ${MEM}
TEND=$(date +%s)
DUREE=$(( $TEND - $TSTAMP ))
echo "$(date) ${BASEDIR}/$SCRIPTNAME ${LAUNCHED} by $USER  duree : ${DUREE}" >> ${BASEDIR}/LOGS/LOGEXEC_all_scrips.log
