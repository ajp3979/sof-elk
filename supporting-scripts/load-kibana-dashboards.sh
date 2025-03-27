#!/bin/bash
# SOF-ELK Kibana Data Import Script

# Set defaults
es_host=localhost
es_port=9200
kibana_host=localhost
kibana_port=5601
kibana_index=.kibana
sofelk_root_dir="/usr/share/kibana/"
kibana_file_dir="${sofelk_root_dir}kibana/"

echo "🚀 Starting Kibana Data Import for Kibana 7.17.14..."

# Set Kibana defaults
echo "🔄 Setting Kibana Defaults..."
curl -s -X POST "http://${kibana_host}:${kibana_port}/api/kibana/settings" \
     -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
     --data-binary @"${kibana_file_dir}/sof-elk_config.json" > /dev/null

# Import Data Views (Index Patterns)
echo "🚀 Importing Data Views (Index Patterns)..."
for dataviewfile in ${kibana_file_dir}/data_views/*.json; do
    dataview_name=$(basename "${dataviewfile}" .json)
    echo "📌 Importing Data View: ${dataview_name}"

    # Extract correct title (pattern name) from the JSON file
    index_pattern_title=$(jq -r '.title' "${dataviewfile}")
    
    # Ensure title is not empty
    if [[ -z "$index_pattern_title" || "$index_pattern_title" == "null" ]]; then
        index_pattern_title="${dataview_name}*"
    fi

    # Delete existing Data View
    curl -s -X DELETE "http://${kibana_host}:${kibana_port}/api/saved_objects/index-pattern/${dataview_name}" \
         -H 'kbn-xsrf: true' > /dev/null

    # Create the new Data View
    dataview_payload=$(jq -n \
        --arg title "$index_pattern_title" \
        --arg name "$dataview_name" \
        '{attributes: {title: $title, name: $name}}')

    curl -s -X POST "http://${kibana_host}:${kibana_port}/api/saved_objects/index-pattern/${dataview_name}" \
         -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
         -d "${dataview_payload}" > /dev/null
done

# Convert JSON saved objects to NDJSON for bulk import
echo "🔄 Converting JSON files to NDJSON for bulk import..."
TMPNDJSONFILE=$(mktemp --suffix=.ndjson)

for objecttype in search visualization lens map dashboard; do
    echo "📌 Processing: $objecttype"
    find "${kibana_file_dir}/${objecttype}" -type f -name '*.json' -exec cat {} \; | jq -c '.' >> "$TMPNDJSONFILE"
done

# Import Saved Objects into Kibana
echo "🚀 Importing Kibana Saved Objects..."
response=$(curl -s -X POST "http://${kibana_host}:${kibana_port}/api/saved_objects/_import?overwrite=true" \
     -H "kbn-xsrf: true" --form file=@"$TMPNDJSONFILE")

echo "📌 Import Response: $response"

if echo "$response" | grep -q '"success":false'; then
    echo "❌ Error importing saved objects. Check response above."
else
    echo "✅ Kibana dashboards and visualizations imported successfully!"
fi

rm -f "$TMPNDJSONFILE"
