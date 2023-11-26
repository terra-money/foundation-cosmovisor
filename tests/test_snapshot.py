import os
import sys
import pytest
import hashlib
import lz4.frame
import tarfile
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'bin')))
import snapshot

def get_sha256_of_file(file_path):
    sha256_hash = hashlib.sha256()

    # Open the file in binary mode and read chunks
    with open(file_path, "rb") as file:
        for byte_block in iter(lambda: file.read(4096), b""):
            sha256_hash.update(byte_block)

    return sha256_hash.hexdigest()

def test_download_file(tmp_path):
    # Use pytest's tmp_path fixture for temporary file handling
    url = 'https://github.com/CosmWasm/wasmvm/releases/download/v1.2.4/libwasmvm.x86_64.so'
    destination = tmp_path / 'libwasmvm.x86_64.so'
    
    snapshot.download_file(url, destination)

    # Check if the file was downloaded and saved successfully
    assert os.path.exists(destination)

    # Check if the downloaded file has the correct content
    checksum = get_sha256_of_file(destination)
    assert checksum == '308a49d5e0f7d34f3e3486b8583c80af7147ccd2290ad4c8052dae65c3c0dabf'

def test_remove_first_directory():
    # Test with a full a directory
    full_path = "/path/to/directory/file.txt"
    expected_result = "to/directory/file.txt"
    assert snapshot.remove_first_directory(full_path) == expected_result

    # # Test with a full path that does not include a directory
    # full_path = "/file.txt"
    # expected_result = "file.txt"
    # assert snapshot.remove_first_directory(full_path) == expected_result

    # # Test with an empty path
    # full_path = ""
    # expected_result = ""
    # assert snapshot.remove_first_directory(full_path) == expected_result

    # Test with a path that includes a single directory
    full_path = "/directory/"
    expected_result = ""
    assert snapshot.remove_first_directory(full_path) == expected_result

# Define your test cases
@patch('os.walk')
@patch('lz4.frame.open')
@patch('tarfile.open')
def test_compress_lz4_with_mocks(mock_tarfile_open, mock_lz4_open, mock_os_walk):
    # Arrange (Set up any necessary test data or context)
    filename = 'test.tar.lz4'
    directories_to_tar = [os.path.dirname(__file__)]
    exclude_patterns = ['*.log', '*.tmp']

    # Act (Call the function you want to test)
    snapshot.compress_lz4(filename, directories_to_tar, exclude_patterns)

    # Assert (Check the expected interactions with mocks)
    # Here you can use assertions to verify that the function called the mocked dependencies as expected
    mock_os_walk.assert_called_with(os.path.dirname(__file__))
    mock_lz4_open.assert_called_with('test.tar.lz4', mode='wb')
    mock_tarfile_open.assert_called_with(fileobj=mock_lz4_open.return_value.__enter__.return_value, mode='w|')

# Create a fixture to set up a temporary test directory
@pytest.fixture
def temp_test_directory(tmpdir):
    return str(tmpdir.mkdir("test_dir"))

# Define your test cases
def test_extract_zip_file(temp_test_directory):
    # Arrange
    zip_file_path = os.path.join(os.path.dirname(__file__), 'data', 'test.zip')
    extract_to = temp_test_directory

    # Act
    result = snapshot.extract_file(zip_file_path, extract_to)

    # Assert
    assert result is True
    extracted_files = os.listdir(extract_to)
    assert len(extracted_files) > 0
    assert 'chains' in extracted_files  # Replace with an actual file name from your test.zip

def test_extract_tar_gz_file(temp_test_directory):
    # Arrange
    tar_gz_file_path = os.path.join(os.path.dirname(__file__), 'data', 'test.tar.gz')
    extract_to = temp_test_directory

    # Act
    result = snapshot.extract_file(tar_gz_file_path, extract_to)

    # Assert
    assert result is True
    extracted_files = os.listdir(extract_to)
    assert len(extracted_files) > 0
    assert 'chains' in extracted_files  # Replace with an actual file name from your test.tar.gz

def test_extract_tar_lz4_file(temp_test_directory):
    # Arrange
    tar_lz4_file_path = os.path.join(os.path.dirname(__file__), 'data', 'test.tar.lz4')
    extract_to = temp_test_directory

    # Act
    result = snapshot.extract_file(tar_lz4_file_path, extract_to)

    # Assert
    assert result is True
    extracted_files = os.listdir(extract_to)
    assert len(extracted_files) > 0
    assert 'chains' in extracted_files  # Replace with an actual file name from your test.tar.lz4

def test_extract_unsupported_file_format(temp_test_directory, caplog):
    # Arrange
    unsupported_file_path = 'test.unknown'
    extract_to = temp_test_directory

    # Act
    result = snapshot.extract_file(unsupported_file_path, extract_to)

    # Assert
    assert result is False
    assert "Unsupported file format" in caplog.text  # Check if the expected error message is logged
