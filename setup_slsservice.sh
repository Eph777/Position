#!/bin/bash

sudo systemctl daemon-reload
sudo systemctl enable sls
sudo systemctl start sls