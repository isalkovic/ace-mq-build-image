# Combined file for easier scripting
export MQSI_SIGNAL_EXCLUSIONS=11
export MQSI_NON_IBM_JAVA=1
export MQSI_NO_CACHE_SUPPORT=1

. /opt/ibm/ace-12/server/bin/mqsiprofile

export LD_LIBRARY_PATH=/lib:/opt/openjdk-15/lib:/opt/openjdk-15/lib/server:$LD_LIBRARY_PATH

# Not really openjdk-related, but still needed
export LD_LIBRARY_PATH=/usr/glibc-compat/zlib-only:$LD_LIBRARY_PATH
