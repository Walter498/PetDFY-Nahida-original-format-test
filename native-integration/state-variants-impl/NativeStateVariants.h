#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* Candidate for the audited PetDFY dylib only. Compile this translation unit with ARC.
 * No constructor, prefs, init replacement, filesystem writes or automatic installation.
 * Caller MUST finish Validate(privateRoot) and mark its private asset-path mapping first.
 * Call Install once on the render-serialization queue, before any rig is marked.
 * The BOOL is a deliberate integration interlock, NOT device acceptance certification.
 */
FOUNDATION_EXPORT BOOL NSVInstall(BOOL enableUnvalidatedCandidate, NSError **error);
/* Pass the ACTUAL returned rig, never the allocated pre-init object. Load variants from
 * the same already validated privateRoot. The module rechecks shape, not asset hashes.
 * Mark once before publishing the rig to a renderer. A replacement rig needs a new mark.
 * The /native/nahida suffix is only a layout sanity check, NOT trust/capability proof;
 * e.g. R/originals/native/nahida is accepted. Caller owns root/contract/hash validation.
 */
FOUNDATION_EXPORT BOOL NSVMarkVerifiedNahidaRig(id rig, NSURL *privateRoot,
                                               NSDictionary *variants, NSError **error);
/* Status: marked, state, generation, disabled, failure. Only per-instance metadata. */
FOUNDATION_EXPORT NSDictionary *NSVStatus(id rig);
NS_ASSUME_NONNULL_END
