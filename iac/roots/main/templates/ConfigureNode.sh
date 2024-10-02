#!/bin/bash

# Update the system
dnf install python3.11 -y
dnf install python3.11-pip -y
dnf install amazon-cloudwatch-agent -y

# Set the environment variables
%{ for config_key, config_value in config }
export ${config_key}="${config_value}"
%{ endfor ~}

# Download and set up the code
cat > /usr/local/bin/clustering-compute.sh << EOF
#!/bin/bash
for i in 1;do
    %{ for config_key, config_value in config }
    export ${config_key}="${config_value}"
    %{ endfor ~}

    cd /home/ec2-user
    mkdir -p stream_consumer
    cd stream_consumer
    aws s3 sync s3://$${S3_BUCKET_PATH} .

    # Run script
    python3.11 -m pip install -r requirements.txt
    python3.11 process_records.py >> /var/log/clustering-compute-python.log 2>&1
    
done
EOF

# Permission the script
chmod +x /usr/local/bin/clustering-compute.sh

# Sleeping just for things to get settled
sleep 30

# Sending the logs to Cloudwatch
touch /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
    "agent": {
            "run_as_user": "root"
    },
    "logs": {
            "logs_collected": {
                    "files": {
                            "collect_list": [
                                    {
                                            "file_path": "/var/log/clustering-compute.log",
                                            "log_group_class": "STANDARD",
                                            "log_group_name": "/aws/clustering-compute-instance",
                                            "log_stream_name": "{instance_id}",
                                            "retention_in_days": -1
                                    },
                                    {
                                            "file_path": "/var/log/clustering-compute-python.log",
                                            "log_group_class": "STANDARD",
                                            "log_group_name": "/aws/clustering-compute-python",
                                            "log_stream_name": "{instance_id}",
                                            "retention_in_days": -1
                                    }                                    
                            ]
                    }
            }
    }
}
EOF

# Start the Cloudwatch Agent
systemctl enable amazon-cloudwatch-agent.service
systemctl start amazon-cloudwatch-agent.service
systemctl status amazon-cloudwatch-agent.service

# Create and Install it as a service
cat > /etc/systemd/system/clustering-compute.service << EOF
[Unit]
Description=Clustering Compute Process
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/clustering-compute.sh
RestartSec=300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start the clustering-compute.service
systemctl daemon-reload
systemctl enable clustering-compute.service
systemctl start clustering-compute.service
systemctl status clustering-compute.service
