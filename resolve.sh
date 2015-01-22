#!/usr/bin/env sh

if [ -z $2 ]; then
  echo "SSL certificate chain resolver"
  echo
  echo "Usage: $0 input.pem output.pem"
  echo
  echo "All certificates are in Base64-encoded PEM format."
  exit
fi


FILENAME=$1
OUTPUT_FILENAME=$2

> $OUTPUT_FILENAME # clear output file


# extract the first certificate from input file, to make this script idempotent
CURRENT_CERT=$(openssl x509 -in $FILENAME)

# loop over certificate chain using AIA extension, CA Issuers field
I=1
while true; do
  # convert from PEM to human-readable format (specific fields are parsed below. dirty solution, but it works)
  CURRENT_CERT_TEXT=$(echo "$CURRENT_CERT" | openssl x509 -noout -text)

  # get certificate subject
  CURRENT_SUBJECT=$(echo "$CURRENT_CERT_TEXT" | awk 'BEGIN{FS="Subject: "} NF==2{print $2}')
  if [ -z "$CURRENT_SUBJECT" ]; then
    echo "Error: empty subject"
    exit 1
  fi
  echo "$I: $CURRENT_SUBJECT"

  # append certificate to result
  echo "$CURRENT_CERT" >> $OUTPUT_FILENAME

  # get issuer's certificate URL
  PARENT_URL=$(echo "$CURRENT_CERT_TEXT" | awk 'BEGIN{FS="CA Issuers - URI:"} NF==2{print $2}')
  if [ -z $PARENT_URL ]; then
    break
  fi

  # download issuer's certificate, convert from DER to PEM
  CURRENT_CERT=$(wget -O - $PARENT_URL | openssl x509 -inform der)

  I=$((I+1))
done


echo
echo "Certificate chain complete."
echo "Total $I certificate(s) written."

# verify the certificate chain
openssl verify -untrusted $OUTPUT_FILENAME $OUTPUT_FILENAME > /dev/null
if [ $? != 0 ]; then
  echo "Error: verification failed"
  exit 1
fi
echo "Verified successfully."
