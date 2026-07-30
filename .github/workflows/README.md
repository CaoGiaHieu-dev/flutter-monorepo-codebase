# 🚀 GitHub Actions Workflows

## 📋 Overview

This directory contains automated workflows for code quality, testing, and deployment.

## 🔄 Workflows

### 1. PR Quality Check (`pr_quality_check.yml`)

**Trigger**: Every Pull Request to `main` or `develop`

**Purpose**: Automated quality gate for PRs

**Steps**:
1. ✅ Flutter Analyze (static analysis)
2. 🧪 Run Tests
3. 📊 Check Code Coverage
4. 🤖 AI Code Review (changed files only)
5. 💬 Comment PR with quality report

**Pass Criteria**:
- No static analysis errors/warnings
- All tests pass
- Code coverage > 70% (warning if below)

**Usage**: Automatic on PR creation/update

---

### 2. AI Code Review (`code_review.yml`)

**Trigger**: 
- Pull Requests (changed files)
- Manual dispatch (any scope)

**Purpose**: Detailed AI-powered code review

**Features**:
- 🔍 Reviews changed files in PRs
- 🎯 Manual review with scope selection
- 🌐 Multi-language reports (EN, VI, JA, KO, ZH)
- 📊 Uploads detailed reports as artifacts
- 💬 Comments PR with summary

**Manual Trigger**:
```
Actions → AI Code Review → Run workflow
- Review scope: changed/all/domain/data/presentation
- Language: en/vi/ja/ko/zh
```

**Outputs**:
- Detailed markdown report
- Artifact: `code-review-report-{run_number}`
- PR comment with summary

---

### 3. Scheduled Code Review (`scheduled_code_review.yml`)

**Trigger**:
- Daily: Monday-Friday at 9 AM UTC
- Weekly: Monday at 8 AM UTC
- Manual dispatch

**Purpose**: Regular automated code reviews

**Jobs**:

#### Daily Review
- Reviews files changed in last 24 hours
- Quick feedback on recent changes
- Retention: 7 days

#### Weekly Review
- Full review of all layers (domain, data, presentation, core)
- Runs in parallel (matrix strategy)
- Focus: Architecture + SOLID principles
- Retention: 30 days

#### Security Audit (Manual)
- Full security scan
- Focus: Security vulnerabilities
- Fails on critical security issues
- Retention: 90 days

#### Performance Review (Manual)
- Full performance analysis
- Focus: Performance bottlenecks
- Retention: 30 days

**Manual Trigger**:
```
Actions → Scheduled Code Review → Run workflow
- Review type: daily/weekly/security/performance
- Language: en/vi
```

---

### 4. Flutter Build (`flutter_build.yml`)

**Trigger**: Push to main/develop, PRs

**Purpose**: Build verification

---

### 5. Fastlane (`fastlane.yml`)

**Trigger**: Manual/Release

**Purpose**: Automated deployment

---

## 🔑 Required Secrets

### GEMINI_API_KEY
**Required for**: AI Code Review workflows

**Setup**:
1. Get API key: https://makersuite.google.com/app/apikey
2. Go to: Repository → Settings → Secrets and variables → Actions
3. Click: New repository secret
4. Name: `GEMINI_API_KEY`
5. Value: Your API key
6. Click: Add secret

### GITHUB_TOKEN
**Required for**: PR comments

**Setup**: Automatically provided by GitHub Actions (no setup needed)

---

## 📊 Artifacts

### Code Review Reports
- **Location**: Workflow run → Artifacts
- **Format**: Markdown
- **Contains**: 
  - Summary statistics
  - Priority breakdown
  - Detailed per-file analysis
  - Quality scores
  - Action items

### Quality Reports
- **Location**: PR Quality Check artifacts
- **Contains**:
  - Static analysis output
  - Test results
  - Coverage report
  - AI review results

---

## 🎯 Usage Examples

### Review PR Before Merge
```
1. Create PR
2. Wait for "PR Quality Check" to complete
3. Check PR comment for quality report
4. If AI review ran, download artifact for details
5. Fix any issues
6. Push changes
7. Workflow runs again automatically
```

### Manual Security Audit
```
1. Go to Actions tab
2. Select "Scheduled Code Review"
3. Click "Run workflow"
4. Select:
   - Review type: security
   - Language: en
5. Click "Run workflow"
6. Wait for completion
7. Download "security-audit-{number}" artifact
8. Review findings
```

### Weekly Architecture Review
```
1. Go to Actions tab
2. Select "Scheduled Code Review"
3. Click "Run workflow"
4. Select:
   - Review type: weekly
   - Language: vi (or preferred)
5. Click "Run workflow"
6. Wait for all layer reviews to complete
7. Download artifacts for each layer
8. Review and plan improvements
```

### Review Specific Layer
```
1. Go to Actions tab
2. Select "AI Code Review"
3. Click "Run workflow"
4. Select:
   - Review scope: domain (or data/presentation)
   - Language: en
5. Click "Run workflow"
6. Download artifact
7. Review findings
```

---

## 🔧 Configuration

### Modify Review Frequency

Edit `scheduled_code_review.yml`:

```yaml
on:
  schedule:
    # Daily at 9 AM UTC
    - cron: '0 9 * * 1-5'
    # Weekly on Monday at 8 AM UTC
    - cron: '0 8 * * 1'
```

Cron format: `minute hour day month weekday`

Examples:
- `0 9 * * 1-5` - 9 AM UTC, Monday-Friday
- `0 8 * * 1` - 8 AM UTC, Monday only
- `0 0 * * 0` - Midnight UTC, Sunday only

### Change Review Scope

Edit `code_review.yml` or `pr_quality_check.yml`:

```yaml
# Review only specific folders
--folder lib/domain

# Add focus areas
--focus security,performance

# Change language
--language vi
```

### Adjust Timeouts

```yaml
jobs:
  code-review:
    timeout-minutes: 30  # Increase if needed
```

### Modify Quality Gate

Edit `pr_quality_check.yml`:

```yaml
# Change coverage threshold
if [ "$COVERAGE" -lt 70 ]; then  # Change 70 to desired %
  echo "::warning::Code coverage is below 70%"
fi

# Make coverage a hard requirement
if [ "$COVERAGE" -lt 70 ]; then
  echo "::error::Code coverage is below 70%"
  exit 1  # Fail the build
fi
```

---

## 🐛 Troubleshooting

### Workflow Fails: "API key not found"

**Solution**: Add `GEMINI_API_KEY` secret (see Required Secrets section)

### Workflow Timeout

**Solution**: Increase timeout in workflow file:
```yaml
timeout-minutes: 60  # Increase from 30
```

### No PR Comment Posted

**Possible causes**:
1. GITHUB_TOKEN permissions issue
2. Report file not generated
3. Script error

**Solution**: Check workflow logs for errors

### Artifact Not Found

**Possible causes**:
1. Review didn't run (check logs)
2. No issues found (empty report)
3. Workflow failed before upload

**Solution**: Check workflow status and logs

### Rate Limit Exceeded

**Solution**: Reduce review frequency or increase delay in tool config:
```bash
cd tools/code_review
dart code_review.dart --config
# Set delay to 2000-3000 ms
```

---

## 📈 Best Practices

### 1. Review Before Merge
- Always wait for quality check to pass
- Review AI findings before merging
- Fix critical issues immediately

### 2. Regular Reviews
- Check weekly review reports
- Track improvements over time
- Plan refactoring based on findings

### 3. Security First
- Run security audit before releases
- Fix security issues immediately
- Keep audit reports for compliance

### 4. Performance Monitoring
- Run performance review monthly
- Track performance scores
- Address bottlenecks proactively

### 5. Team Collaboration
- Share review findings in team meetings
- Discuss patterns and improvements
- Update documentation based on learnings

---

## 🔗 Related Documentation

- [Code Review Tool](../../tools/code_review/TOOL_README.md)
- [Usage Guide](../../tools/code_review/USAGE_GUIDE.md)
- [Architecture Documentation](../../docs/01_ARCHITECTURE.md)
- [Testing Guide](../../docs/06_TESTING.md)

---

## 🤝 Contributing

To add or modify workflows:

1. Create/edit workflow file in `.github/workflows/`
2. Test locally if possible
3. Create PR with workflow changes
4. Document changes in this README
5. Update team on new workflows

---

## 📝 Workflow Status Badges

Add to your main README.md:

```markdown
![PR Quality Check](https://github.com/YOUR_ORG/YOUR_REPO/workflows/PR%20Quality%20Check/badge.svg)
![AI Code Review](https://github.com/YOUR_ORG/YOUR_REPO/workflows/AI%20Code%20Review/badge.svg)
```

---

**Last Updated**: 2025-01-10
**Maintained By**: Development Team
