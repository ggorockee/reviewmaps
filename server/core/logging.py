import logging

def setup_logging(level: str = "INFO") -> None:
    root = logging.getLogger()
    if root.handlers:
        return
    
    root.setLevel(level.upper())
    fmt = logging.Formatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s")
    sh  = logging.StreamHandler()
    sh.setFormatter(fmt)
    root.addHandler(sh)