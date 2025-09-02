import sys
import os
import time
import argparse
import importlib
from inspect import isclass
from typing import Optional

from core.config import settings
from core.logger import get_logger
from core.base import BaseScraper

log = get_logger("main")

from scrapers.inflexer import InflexerScraper


inflexer = InflexerScraper()
inflexer.run("강남")