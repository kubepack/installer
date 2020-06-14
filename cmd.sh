#!/bin/bash

msg="Publish a/b@vbc charts"
pr_cmd=$(cat <<EOF
hub pull-request
    --labels ${pr_labels:-automerge}
    --message "Publish a/b@vbc charts"
EOF
)
$pr_cmd
