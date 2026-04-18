# Security Vulnerability Fixes

## Date: 2026-04-10

### Vulnerabilities Addressed (Round 2)

The following security vulnerabilities were identified and patched in `requirements.txt`:

#### 1. **black** (Code Formatter)
- **Vulnerability**: Arbitrary file writes from unsanitized user input in cache file name
- **Previous Version**: 23.12.0 → 24.8.0 (still vulnerable) → **26.3.1** ✅
- **Patched Version**: 26.3.1 (minimum required)
- **Severity**: Medium
- **Impact**: Development dependency only, does not affect production runtime

#### 2. **fastapi** (Web Framework)
- **Vulnerability**: Content-Type Header ReDoS (Regular Expression Denial of Service)
- **Previous Version**: 0.104.1
- **Patched Version**: 0.115.0 ✅
- **Severity**: High
- **Impact**: Production runtime - critical fix

#### 3. **pillow** (Image Processing)
- **Vulnerabilities**: 
  - Buffer overflow vulnerability (v10.1.0)
  - Out-of-bounds write when loading PSD images (v10.4.0)
  - FITS GZIP decompression bomb vulnerability (affects >=10.3.0,<12.2.0)
- **Previous Version**: 10.1.0 → 10.4.0 (still vulnerable) → 12.1.1 (still vulnerable) → **12.2.0** ✅
- **Patched Version**: 12.2.0 (minimum required)
- **Severity**: High
- **Impact**: Production runtime - affects TIFF OCR and any image processing

#### 4. **python-multipart** (File Upload Handler)
- **Vulnerabilities**: 
  - Arbitrary File Write via Non-Default Configuration
  - Denial of Service (DoS) via malformed multipart/form-data boundary
  - Content-Type Header ReDoS
- **Previous Version**: 0.0.6
- **Patched Version**: 0.0.22 ✅
- **Severity**: Critical
- **Impact**: Production runtime - affects file upload security

### Final Vulnerability Status

All dependencies are now updated to secure versions:

| Package | Final Version | Status |
|---------|---------------|--------|
| black | 26.3.1 | ✅ Secure |
| fastapi | 0.115.0 | ✅ Secure |
| pillow | 12.2.0 | ✅ Secure |
| python-multipart | 0.0.22 | ✅ Secure |

### Verification

All dependencies have been updated to versions that meet or exceed the minimum patched versions:

```bash
# Verify updates
pip install -r requirements.txt
pip list | grep -E "black|fastapi|pillow|python-multipart"

# Expected output:
# black        26.3.1
# fastapi      0.115.0
# pillow       12.2.0
# python-multipart  0.0.22
```

### Testing Recommendations

After updating dependencies:

1. **Test File Uploads**
   ```bash
   curl -X POST http://localhost:8000/api/upload \
     -F "file=@test.pdf" \
     -F "case_id=test123"
   ```

2. **Test TIFF/Image Processing** (critical - pillow major version jump)
   - Upload a TIFF file
   - Verify OCR processing completes without errors
   - Test with various image formats (PNG, JPEG, PSD if applicable)

3. **Test API Endpoints**
   - Run health checks
   - Submit test jobs
   - Verify no ReDoS issues with malformed Content-Type headers

4. **Run Test Suite**
   ```bash
   pytest tests/
   ```

### Production Deployment

When deploying to production:

1. Update virtual environment:
   ```bash
   pip install --upgrade -r requirements.txt
   ```

2. Restart services:
   ```bash
   sudo systemctl restart fastapi
   sudo systemctl restart celery-worker
   ```

3. Monitor logs for any compatibility issues

### Important Compatibility Notes

- **Pillow 10.4.0 → 12.2.0**: **MAJOR VERSION JUMP** 🚨
  - This is a significant update across multiple major versions
  - May have breaking API changes
  - **Critical Testing Required**:
    - Test all image processing functionality
    - Test TIFF OCR with pytesseract
    - Test image parsing functions from unified_compare_app.py
  - Review [Pillow changelog](https://pillow.readthedocs.io/en/stable/releasenotes/index.html)

- **black 24.8.0 → 26.3.1**: Major version update for dev tool
  - May format code differently
  - Run `black --check src/` before committing
  - Consider reformatting codebase: `black src/`

- **FastAPI 0.104.1 → 0.115.0**: Minor version update
  - Generally backward compatible
  - Review [release notes](https://github.com/tiangolo/fastapi/releases)

- **python-multipart 0.0.6 → 0.0.22**: Significant version jump
  - Thoroughly test file uploads
  - Test multipart form handling

### Known Potential Issues

#### Pillow 12.2.0 Compatibility

Since Pillow jumped from 10.x to 12.x, potential issues to watch for:

1. **API Changes**:
   - Some deprecated functions may have been removed
   - Check usage of `Image.ANTIALIAS` → use `Image.LANCZOS` instead
   - Verify `ImageOps` functions still work as expected

2. **TIFF Processing**:
   - Test with sample TIFF files
   - Verify pytesseract integration still works
   - Check `parse_tiff()` function from unified_compare_app.py

3. **Performance**:
   - May have performance improvements or regressions
   - Monitor processing times for image files

#### Migration Path

If Pillow 12.2.0 causes issues:

**Option 1**: Stay on latest 10.x (if vulnerabilities are acceptable in your environment)
```python
pillow==10.4.0  # Still has out-of-bounds write vulnerability
```

**Option 2**: Use 11.x as intermediate (check if it's patched)
```bash
pip install "pillow>=11.0,<12.0"
# Then check for vulnerabilities
```

**Option 3**: Fix code compatibility with 12.2.0 (recommended)
- Review Pillow migration guides
- Update image processing code as needed
- This is the most secure long-term solution

### Additional Security Recommendations

1. **Regular Dependency Audits**
   ```bash
   pip install pip-audit
   pip-audit
   
   # Or use safety
   pip install safety
   safety check
   ```

2. **Automated Security Scanning**
   - Add Dependabot to repository
   - Configure weekly dependency scans
   - Enable automated security updates for development dependencies

3. **Pin Dependencies**
   - Current approach uses exact versions (good!)
   - Update only after testing in development
   - Document testing process for each update

4. **Production Hardening**
   - Ensure all .env files have secure values
   - Validate file uploads beyond extension checks
   - Implement rate limiting on upload endpoints
   - Use WAF (Web Application Firewall) if available
   - Consider file upload virus scanning

5. **Vulnerability Response Process**
   - Subscribe to security advisories for key dependencies
   - Test patches in dev environment first
   - Have rollback plan ready

### Testing Checklist

Before deploying to production:

- [ ] Install updated requirements.txt
- [ ] Run pytest test suite (if exists)
- [ ] Test file uploads (all supported types)
- [ ] Test TIFF OCR processing specifically
- [ ] Test image processing functions
- [ ] Verify FastAPI endpoints respond correctly
- [ ] Check that black still formats code (dev)
- [ ] Load test file upload endpoint
- [ ] Monitor error logs during testing
- [ ] Verify no regression in functionality

### Status

✅ All known vulnerabilities patched with latest secure versions
✅ Requirements.txt updated  
⚠️ **CRITICAL**: Pillow major version jump requires thorough testing
⏳ Testing in development environment **strongly recommended**
⏳ Production deployment pending testing

### Breaking Change Risk Assessment

| Package | Risk Level | Action Required |
|---------|------------|-----------------|
| black | 🟡 Low | Reformat code, dev only |
| fastapi | 🟢 Minimal | Review release notes |
| pillow | 🔴 **High** | **Extensive testing required** |
| python-multipart | 🟡 Medium | Test file uploads |

---

**Next Action**: 
1. **Immediately test Pillow 12.2.0 compatibility** with TIFF OCR and image processing
2. If issues arise, document them and determine mitigation strategy
3. Only deploy to production after successful testing

**Priority**: The Pillow update is critical for security but requires careful validation due to the major version jump.
