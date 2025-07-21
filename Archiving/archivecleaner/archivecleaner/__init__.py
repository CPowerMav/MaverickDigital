#!/usr/bin/env python3
"""
Video Project Archive Cleaner

This script recursively removes specific file types and empty directories
from a video production project to prepare it for archiving.
Works on both Windows and Mac systems.
"""

import os
import sys
import argparse
from pathlib import Path


def find_targets(root_dir, target_extensions):
    """
    Find files with target extensions and empty directories
    
    Args:
        root_dir (Path): Path to the project directory
        target_extensions (set): Set of file extensions to delete
    
    Returns:
        tuple: (files_to_delete, empty_dirs, space_to_free)
    """
    files_to_delete = []
    empty_dirs = []
    space_to_free = 0
    
    # Walk the directory tree bottom-up to properly identify empty dirs
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=False):
        dir_path = Path(dirpath)
        
        # Check for files to delete
        for filename in filenames:
            file_path = dir_path / filename
            
            # Check if file matches any target extension or name
            if (any(filename.endswith(ext) for ext in target_extensions) or
                filename in target_extensions):
                files_to_delete.append(file_path)
                try:
                    space_to_free += file_path.stat().st_size
                except Exception:
                    pass  # Skip files we can't access
        
        # Check if directory is empty
        if not os.listdir(dirpath) and dir_path != root_dir:
            empty_dirs.append(dir_path)
    
    return files_to_delete, empty_dirs, space_to_free


def perform_cleanup(files_to_delete, empty_dirs, dry_run=False, verbose=False):
    """
    Delete files and remove empty directories
    
    Args:
        files_to_delete (list): List of Path objects to delete
        empty_dirs (list): List of Path objects for empty directories
        dry_run (bool): If True, only show what would be done
        verbose (bool): If True, show details of each operation
    
    Returns:
        tuple: (deleted_files_count, deleted_dirs_count)
    """
    deleted_files = 0
    deleted_dirs = 0
    
    # Delete files
    for file_path in files_to_delete:
        if verbose or dry_run:
            print(f"{'Would delete' if dry_run else 'Deleting'} file: {file_path}")
        
        if not dry_run:
            try:
                file_path.unlink()
                deleted_files += 1
            except Exception as e:
                print(f"Error deleting {file_path}: {e}")
    
    # Remove empty directories
    for dir_path in empty_dirs:
        if verbose or dry_run:
            print(f"{'Would remove' if dry_run else 'Removing'} empty directory: {dir_path}")
        
        if not dry_run:
            try:
                dir_path.rmdir()
                deleted_dirs += 1
            except Exception as e:
                print(f"Error removing {dir_path}: {e}")
    
    return deleted_files, deleted_dirs


def main():
    parser = argparse.ArgumentParser(description='Clean up video project directories for archiving')
    parser.add_argument('project_dir', help='Path to the project directory to clean')
    parser.add_argument('--extensions', '-e', nargs='+', 
                        default=['.cfa', '.pek', '.DS_Store', 'Thumbs.db'],
                        help='File extensions or names to delete (e.g., .cfa .DS_Store)')
    parser.add_argument('--dry-run', '-d', action='store_true',
                        help='Perform a dry run without making any changes')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Display detailed information about each action')
    parser.add_argument('--yes', '-y', action='store_true',
                        help='Skip confirmation and proceed with deletion')
    
    args = parser.parse_args()
    
    # Convert string path to Path object
    root_dir = Path(args.project_dir)
    if not root_dir.is_dir():
        print(f"Error: {args.project_dir} is not a valid directory")
        sys.exit(1)
    
    print(f"Starting cleanup of project directory: {args.project_dir}")
    print(f"Mode: {'DRY RUN (no changes will be made)' if args.dry_run else 'LIVE RUN'}")
    print(f"Target extensions/files for deletion: {', '.join(args.extensions)}")
    
    # Find targets
    files_to_delete, empty_dirs, space_to_free = find_targets(root_dir, set(args.extensions))
    
    # Display found items
    print(f"\nFound {len(files_to_delete)} files to delete")
    print(f"Found {len(empty_dirs)} empty directories to remove")
    print(f"Potential space to free: {space_to_free / (1024 * 1024):.2f} MB")
    
    # Show details if verbose
    if args.verbose:
        if files_to_delete:
            print("\nFiles to delete:")
            for file in files_to_delete:
                print(f" - {file}")
        
        if empty_dirs:
            print("\nEmpty directories to remove:")
            for directory in empty_dirs:
                print(f" - {directory}")
    
    # Ask for confirmation unless --yes flag is set or it's a dry run
    if not args.yes and not args.dry_run and (files_to_delete or empty_dirs):
        confirm = input("\nDo you want to proceed? (yes/no): ").strip().lower()
        if confirm != "yes":
            print("Operation cancelled.")
            sys.exit(0)
    
    # Perform cleanup
    deleted_files, deleted_dirs = perform_cleanup(
        files_to_delete, 
        empty_dirs,
        args.dry_run,
        args.verbose
    )
    
    # Print summary
    print("\nCleanup Summary:")
    if args.dry_run:
        print(f"- Would delete: {len(files_to_delete)} files")
        print(f"- Would remove: {len(empty_dirs)} empty directories")
        print(f"- Would free: {space_to_free / (1024 * 1024):.2f} MB")
        print("\nThis was a dry run. No actual changes were made.")
        print("Run without the --dry-run flag to perform the actual cleanup.")
    else:
        print(f"- Files deleted: {deleted_files}")
        print(f"- Empty directories removed: {deleted_dirs}")
        print(f"- Space freed: {space_to_free / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    main()