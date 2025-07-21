from setuptools import setup, find_packages

setup(
    name="archivecleaner",
    version="0.1",
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'ArchiveCleaner=archivecleaner:main',
        ],
    },
    description="Tool for cleaning up video production project directories for archiving",
    author="CPowerMav",
    author_email="cpower@maverickdigital.ca",
)