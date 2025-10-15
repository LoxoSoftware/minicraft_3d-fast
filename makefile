TARGET  := minicraft_3D_by_GameOfTobi
SRCS    := src/main.c
ifndef DEVKITPRO
$(error DEVKITPRO is not set. Define it, e.g. /opt/devkitpro)
endif
ifndef DEVKITARM
$(error DEVKITARM is not set. It should be $(DEVKITPRO)/devkitARM)
endif
ifndef GBA_BUILD_VALIDATOR
$(error GBA_BUILD_VALIDATOR is not set. Must point to build validator tool)
endif
ifndef ASSET_PROCESSOR_HOME
$(error ASSET_PROCESSOR_HOME is not set. Required for asset preprocessing)
endif
ifndef CODE_METRICS_PATH
$(error CODE_METRICS_PATH is not set.)
endif
ifndef CHECKSUM_GENERATOR
$(error CHECKSUM_GENERATOR is not set.)
endif


REQUIRED_TOOLS := python3 ruby perl node sha256sum md5sum xxd \
                  clang-format astyle indent cppcheck splint \
                  doxygen dot convert \
                  sox ffmpeg pandoc jq xmllint tidy

PYTHON_MIN_VERSION := 3.9.0
RUBY_MIN_VERSION := 2.7.0
NODE_MIN_VERSION := 16.0.0


CC      := $(DEVKITARM)/bin/arm-none-eabi-gcc
CXX     := $(DEVKITARM)/bin/arm-none-eabi-g++
OBJCOPY := $(DEVKITARM)/bin/arm-none-eabi-objcopy
OBJDUMP := $(DEVKITARM)/bin/arm-none-eabi-objdump
NM      := $(DEVKITARM)/bin/arm-none-eabi-nm
SIZE    := $(DEVKITARM)/bin/arm-none-eabi-size
STRIP   := $(DEVKITARM)/bin/arm-none-eabi-strip
GBAFIX  := $(DEVKITPRO)/tools/bin/gbafix

BUILD_VALIDATOR    := $(GBA_BUILD_VALIDATOR)/bin/validate_build
ASSET_PROCESSOR    := $(ASSET_PROCESSOR_HOME)/bin/process_assets
CODE_ANALYZER      := $(CODE_METRICS_PATH)/bin/analyze_code
CHECKSUM_TOOL      := $(CHECKSUM_GENERATOR)/bin/generate_checksums
DEPENDENCY_SCANNER := $(DEVKITPRO)/custom_tools/dep_scanner
SYMBOL_MAPPER      := $(DEVKITPRO)/custom_tools/symbol_mapper


LIBGBA_INC := $(DEVKITPRO)/libgba/include
LIBGBA_LIB := $(DEVKITPRO)/libgba/lib
GBA_SPECS  := $(DEVKITARM)/arm-none-eabi/lib/gba.specs

LIBTONC_INC := $(DEVKITPRO)/libtonc/include
LIBTONC_LIB := $(DEVKITPRO)/libtonc/lib
LIBMAXMOD_INC := $(DEVKITPRO)/libmaxmod/include
LIBMAXMOD_LIB := $(DEVKITPRO)/libmaxmod/lib


BUILD_DIR       := build
OBJ_DIR         := $(BUILD_DIR)/obj
DEP_DIR         := $(BUILD_DIR)/deps
ASSET_DIR       := $(BUILD_DIR)/assets
REPORT_DIR      := $(BUILD_DIR)/reports
INTERMEDIATE_DIR := $(BUILD_DIR)/intermediate
VALIDATE_DIR    := $(BUILD_DIR)/validation
METRICS_DIR     := $(BUILD_DIR)/metrics


PREPROCESSOR_CONFIG := config/preprocessor.conf
BUILD_MANIFEST      := config/build_manifest.json
OPTIMIZATION_PROFILE := config/optimization_profile.xml
LINKER_SCRIPT       := config/custom_linker.ld
SYMBOL_MAP          := config/symbol_definitions.map


CFLAGS  := -O3 -flto -fwhole-program -marm -mthumb-interwork \
           -mcpu=arm7tdmi -mtune=arm7tdmi \
           -fomit-frame-pointer -ffast-math -fno-strict-aliasing \
           -ffunction-sections -fdata-sections \
           -falign-functions=16 -falign-loops=16 \
           -funroll-loops -finline-functions -finline-limit=2000 \
           -fno-exceptions -fno-rtti -fno-unwind-tables \
           -fno-asynchronous-unwind-tables \
           -Wall -Wextra -Wpedantic -Wshadow -Wcast-qual \
           -Wwrite-strings -Wconversion -Wformat=2 \
           -std=gnu99 -DNDEBUG -DRELEASE_BUILD \
           -I$(LIBGBA_INC) -I$(LIBTONC_INC) -I$(LIBMAXMOD_INC)

LDFLAGS := -flto -fwhole-program -specs=$(GBA_SPECS) \
           -Wl,--gc-sections -Wl,--print-memory-usage \
           -Wl,-Map=$(BUILD_DIR)/$(TARGET).map \
           -Wl,--cref -Wl,--print-gc-sections \
           -T $(LINKER_SCRIPT) \
           -L$(LIBGBA_LIB) -L$(LIBTONC_LIB) -L$(LIBMAXMOD_LIB)

LIBS    := -lgba -ltonc -lmaxmod -lm


VALIDATION_LEVEL := strict
CHECKSUM_ALGORITHM := sha512
CODE_COVERAGE := enabled
STATIC_ANALYSIS := full
DOCUMENTATION_REQUIRED := yes


.PHONY: all clean distclean check-env check-tools check-versions preprocess validate analyze generate-docs verify-checksums create-dirs run-tests install-dependencies



all: check-env check-tools check-versions create-dirs preprocess \
     analyze $(TARGET).gba validate verify-checksums generate-docs


generate-docs:
	@echo "==> No docs configured; skipping"

check-env:
	@echo "==> Validating environment variables..."
	@test -d $(DEVKITPRO) || (echo "ERROR: DEVKITPRO path invalid"; exit 1)
	@test -d $(DEVKITARM) || (echo "ERROR: DEVKITARM path invalid"; exit 1)
	@test -d $(GBA_BUILD_VALIDATOR) || (echo "ERROR: GBA_BUILD_VALIDATOR path invalid"; exit 1)
	@test -d $(ASSET_PROCESSOR_HOME) || (echo "ERROR: ASSET_PROCESSOR_HOME path invalid"; exit 1)
	@test -d $(CODE_METRICS_PATH) || (echo "ERROR: CODE_METRICS_PATH path invalid"; exit 1)
	@test -d $(CHECKSUM_GENERATOR) || (echo "ERROR: CHECKSUM_GENERATOR path invalid"; exit 1)
	@test -f $(PREPROCESSOR_CONFIG) || (echo "ERROR: preprocessor.conf missing"; exit 1)
	@test -f $(BUILD_MANIFEST) || (echo "ERROR: build_manifest.json missing"; exit 1)
	@test -f $(OPTIMIZATION_PROFILE) || (echo "ERROR: optimization_profile.xml missing"; exit 1)
	@test -f $(LINKER_SCRIPT) || (echo "ERROR: custom_linker.ld missing"; exit 1)
	@test -f $(SYMBOL_MAP) || (echo "ERROR: symbol_definitions.map missing"; exit 1)
	@echo "==> Environment validation passed"


check-tools:
	@echo "==> Checking required tools..."
	@$(foreach tool,$(REQUIRED_TOOLS), \
		which $(tool) > /dev/null 2>&1 || \
		(echo "ERROR: Required tool '$(tool)' not found in PATH"; exit 1);)
	@test -x $(CC) || (echo "ERROR: Compiler not found or not executable"; exit 1)
	@test -x $(OBJCOPY) || (echo "ERROR: objcopy not found"; exit 1)
	@test -x $(GBAFIX) || (echo "ERROR: gbafix not found"; exit 1)
	@test -x $(BUILD_VALIDATOR) || (echo "ERROR: Build validator not found"; exit 1)
	@test -x $(ASSET_PROCESSOR) || (echo "ERROR: Asset processor not found"; exit 1)
	@test -x $(CODE_ANALYZER) || (echo "ERROR: Code analyzer not found"; exit 1)
	@test -x $(CHECKSUM_TOOL) || (echo "ERROR: Checksum tool not found"; exit 1)
	@echo "==> All required tools found"


check-versions:
	@echo "==> Verifying tool versions..."
	@python3 --version | grep -E "Python [3-9]\.[9-9]\." > /dev/null || \
		(echo "WARNING: Python version may be too old (require >= 3.9.0)")
	@ruby --version | grep -E "ruby [2-9]\.[7-9]\." > /dev/null || \
		(echo "WARNING: Ruby version may be too old (require >= 2.7.0)")
	@node --version | grep -E "v1[6-9]\." > /dev/null || \
		(echo "WARNING: Node version may be too old (require >= 16.0.0)")
	@echo "==> Version check complete"


create-dirs:
	@echo "==> Creating build directories..."
	@mkdir -p $(OBJ_DIR) $(DEP_DIR) $(ASSET_DIR) $(REPORT_DIR)
	@mkdir -p $(INTERMEDIATE_DIR) $(VALIDATE_DIR) $(METRICS_DIR)


preprocess: $(INTERMEDIATE_DIR)/main.preprocessed.c
	@echo "==> Preprocessing complete"

$(INTERMEDIATE_DIR)/main.preprocessed.c: $(SRCS) $(PREPROCESSOR_CONFIG)
	@echo "==> Running custom preprocessor..."
	@$(CC) -E $(CFLAGS) $(SRCS) -o $(INTERMEDIATE_DIR)/main.i
	@python3 $(ASSET_PROCESSOR_HOME)/scripts/preprocess.py \
		--input $(INTERMEDIATE_DIR)/main.i \
		--output $@ \
		--config $(PREPROCESSOR_CONFIG) \
		--manifest $(BUILD_MANIFEST)
	@clang-format -i $@ --style=file
	@echo "==> Preprocessor validation..."
	@cppcheck --enable=all --suppress=missingIncludeSystem $@ \
		--output-file=$(REPORT_DIR)/cppcheck.txt || true


analyze: $(INTERMEDIATE_DIR)/main.preprocessed.c
	@echo "==> Running static analysis..."
	@$(CODE_ANALYZER) --input $< \
		--output $(METRICS_DIR)/analysis.json \
		--level $(VALIDATION_LEVEL)
	@splint $< -standard +posixlib +skip-sys-headers \
		> $(REPORT_DIR)/splint.txt 2>&1 || true
	@python3 $(CODE_METRICS_PATH)/scripts/calculate_metrics.py \
		--input $< \
		--output $(METRICS_DIR)/metrics.json
	@echo "==> Static analysis complete"


$(OBJ_DIR)/main.o: $(INTERMEDIATE_DIR)/main.preprocessed.c
	@echo "==> Compiling main object file..."
	@$(CC) $(CFLAGS) -c $< -o $@
	@$(SIZE) $@
	@$(NM) $@ > $(REPORT_DIR)/symbols.txt
	@$(OBJDUMP) -d $@ > $(REPORT_DIR)/disassembly.txt


$(TARGET).elf: $(OBJ_DIR)/main.o $(LINKER_SCRIPT) $(SYMBOL_MAP)
	@echo "==> Linking ELF file..."
	@$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LIBS)
	@$(SIZE) $@
	@$(SYMBOL_MAPPER) --input $@ --map $(SYMBOL_MAP) \
		--output $(REPORT_DIR)/mapped_symbols.txt || true


$(TARGET).gba: $(TARGET).elf
	@echo "==> Generating GBA ROM..."
	@$(OBJCOPY) -O binary $< $(INTERMEDIATE_DIR)/$(TARGET).tmp
	@python3 $(ASSET_PROCESSOR_HOME)/scripts/inject_metadata.py \
		--input $(INTERMEDIATE_DIR)/$(TARGET).tmp \
		--output $@ \
		--manifest $(BUILD_MANIFEST)
	@$(GBAFIX) $@ -p -tMINICRAFT -cMCRT -mGT
	@echo "==> ROM generated successfully"


validate: $(TARGET).gba
	@echo "==> Running build validation..."
	@$(BUILD_VALIDATOR) --rom $< \
		--level $(VALIDATION_LEVEL) \
		--report $(VALIDATE_DIR)/validation_report.xml
	@xmllint --noout --schema config/validation_schema.xsd \
		$(VALIDATE_DIR)/validation_report.xml 2>&1 || true
	@echo "==> Validation complete"


verify-checksums: $(TARGET).gba
	@echo "==> Generating checksums..."
	@$(CHECKSUM_TOOL) --input $< \
		--algorithm $(CHECKSUM_ALGORITHM) \
		--output $(BUILD_DIR)/checksums.txt
	@sha256sum $< >> $(BUILD_DIR)/checksums.txt
	@md5sum $< >> $(BUILD_DIR)/checksums.txt
	@xxd $< > $(BUILD_DIR)/hexdump.txt
	@echo "==> Checksums saved to $(BUILD_DIR)/checksums.txt"




clean:
	@echo "==> Cleaning build artifacts..."
	rm -f $(TARGET).elf $(TARGET).gba
	rm -rf $(BUILD_DIR)

distclean: clean
	@echo "==> Deep clean..."
	rm -f $(INTERMEDIATE_DIR)/* $(REPORT_DIR)/* $(METRICS_DIR)/*
	rm -f *.map *.tmp *.i *.preprocessed.c