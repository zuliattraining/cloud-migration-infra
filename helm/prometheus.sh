#!/bin/bash

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo update

#helm install prometheus prometheus-community/prometheus \
helm install monitoring prometheus-community/kube-prometheus-stack \
-f monitoring/prometheus-values.yaml \
-n monitoring \
--create-namespace