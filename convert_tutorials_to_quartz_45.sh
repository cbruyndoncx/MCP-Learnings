#!/bin/bash

# Exit immediately if a command exits with a non-zero status
#set -e

# Enable extended globbing and treat null as a pattern that matches no files
shopt -s globstar nullglob

# Check if a start directory is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <start_directory>"
  exit 1
fi

# Declare associative arrays to map old filenames to new filenames and to store directory titles
declare -A blog_map
declare -A dir_titles

# 1. Remove dots from directory names
echo "Starting to remove dots from directory names..."
# Find all directories containing dots and rename them by removing dots
find "$1" -type d -name "*.*" | while read -r dir; do
  newdir="${dir//./}"
  if [[ "$dir" != "$newdir"  && $newdir != '' ]]; then
    mv "$dir" "$newdir"
    echo "Renamed directory: $dir -> $newdir"
  fi
done
echo "Finished removing dots from directory names."

# make the README the index page show it shows together with any file content
mv $1/README.md $1/index.md

# Rebuild file list after renaming directories
echo "Rebuilding file list..."
mapfile -t files < <(find "$1" -type f -name "*.md")
echo "File list rebuilt."

# Loop through each markdown file found
echo "Processing markdown files..."
for file in "${files[@]}"; do
  echo "Processing file: $file"
  
  # Check if file contains a Blog header with number
  blog_header=$(grep -m1 '^## Blog [0-9]\+' "$file")
  if [[ -n "$blog_header" ]]; then
    # Extract blog number from header
    blog_number=$(echo "$blog_header" | sed -E 's/^## Blog ([0-9]+).*/\1/')
    
    # Map blog files to blog-<number>.md
    dir=$(dirname "$file")
    newname="$dir/blog-$blog_number.md"
    blog_map["$file"]="$newname"
    echo "Mapped blog file $file to $newname"
    
    # Save directory title for index.md (with dots removed)
    clean_dir=$(basename "${dir//./}")
    dir_titles["$dir"]="$clean_dir"
    echo "Saved directory title: $clean_dir"
  else
    echo "Skipping non-blog file: $file"
  fi
done
echo "Finished processing markdown files."

# Debugging: Print blog_map contents
echo "Blog map contents:"
for oldfile in "${!blog_map[@]}"; do
  echo "Old file: $oldfile -> New file: ${blog_map[$oldfile]}"
done

# 2. Ensure index.md with correct title in each directory (always creates or overwrites)
echo "Creating/Updating index.md files..."
# Loop through each directory that has a title stored in dir_titles
for dir in "${!dir_titles[@]}"; do
  index_file="$dir/index.md"
  title="${dir_titles[$dir]}"
  echo -e "---\ntitle: \"$title\"\n---\n" > "$index_file"
  echo "Created/updated $index_file with title: $title"
done
echo "Finished creating/updating index.md files."

# 3. Ensure Blogs subdirectory in each directory
echo "Ensuring Blogs subdirectory in each directory..."
for dir in "${!dir_titles[@]}"; do
  blogs_dir="$dir/Blogs"
  if [ ! -d "$blogs_dir" ]; then
    mkdir "$blogs_dir"
    echo "Created Blogs subdirectory: $blogs_dir"
  fi
done
echo "Finished ensuring Blogs subdirectory in each directory."

# 4. Process files, add/update frontmatter, move to Blogs directory
# 4. Process files, add/update frontmatter, move to Blogs directory
echo "Adding/updating frontmatter and moving files..."
for file in "${!blog_map[@]}"; do
  echo "Processing file: $file"
  newfile="${blog_map[$file]}"
  dir=$(dirname "$file")
  blogs_dir="$dir/Blogs"
  destination="$blogs_dir/$(basename "$newfile")"  # Use newfile instead of newname

  # Extract title from first ## line
  line=$(grep -m1 '^## ' "$file")
  if [[ -n "$line" ]]; then
    title=$(echo "$line" | sed -E 's/^##[[:space:]]*//; s/[[:space:]]*:?$//')
    echo "Extracted title: $title"
  else
    # If no ## header is found, use filename as title
    title=$(basename "$file" .md)
    echo "Using filename as title: $title"
  fi

  # Remove leading content up to and including first ## line
  if [[ -n "$line" ]]; then
    awk '/^## /{found=1} !found{next} {print}' "$file" > "${file}.body"
    echo "Removed leading content up to and including first ## line"
  else
    cp "$file" "${file}.body"
    echo "Copied file content to ${file}.body"
  fi

  # Create/update frontmatter in new file
  {
    echo "---"
    echo "title: \"$title\""
    echo "draft: false"
    echo "---"
    cat "${file}.body"
  } > "$destination"
  echo "Created/updated $destination with frontmatter"

  # Remove temporary body file
  rm "${file}.body"
  echo "Removed temporary body file: ${file}.body"

  # Remove original file if renamed
  if [[ "$newfile" != "$file" ]]; then
    rm "$file"
    echo "Removed original file: $file"
  fi
done
echo "Finished adding/updating frontmatter and moving files."

# 5. Link rewriting (now done in Blogs directory)
echo "Rewriting links in blog files..."
# Process each blog file to update links
for file in "${!blog_map[@]}"; do
  newfile="${blog_map[$file]}"
  blogs_dir=$(dirname "$file")/Blogs
  destination="$blogs_dir/$(basename "$newfile")"

  # Skip if file doesn't exist
  if [[ ! -f "$destination" ]]; then
    echo "Skipping link rewriting for non-existent file: $destination"
    continue
  fi
  # Prepare sed script for link rewriting
  sed_script=""
  for other_file in "${!blog_map[@]}"; do
    other_newfile="${blog_map[$other_file]}"
    other_basename=$(basename "$other_newfile")
    if [[ "$other_newfile" =~ blog-([0-9]+)\.md$ ]]; then
      num="${BASH_REMATCH[1]}"
      sed_script+="s|link-to-post-$num|$other_basename|g;"
    fi
  done

  # Only apply sed if needed
  if [[ -n "$sed_script" ]]; then
    echo "Rewriting links in $destination..."
    awk '
      /^---$/ {c++; print; next}
      c<2 {print; next}
      {print}
    ' "$destination" | \
    sed -E "$sed_script" > "${destination}.tmp"
    mv "${destination}.tmp" "$destination"
    echo "Finished rewriting links in $destination"
  fi
done
echo "Finished link rewriting."

echo "All blogs processed and renamed."
